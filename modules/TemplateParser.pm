package TemplateParser;

# ************************************************************
# Description   : Parses the template and fills in missing values
# Author        : Chad Elliott
# Create Date   : 5/17/2002
# ************************************************************

# ************************************************************
# Pragmas
# ************************************************************

use strict;

use Parser;

use vars qw(@ISA);
@ISA = qw(Parser);

# ************************************************************
# Data Section
# ************************************************************

my(%keywords) = ('if'              => 1,
                 'else'            => 1,
                 'endif'           => 1,
                 'noextension'     => 1,
                 'dirname'         => 1,
                 'basename'        => 1,
                 'basenoextension' => 1,
                 'foreach'         => 1,
                 'forfirst'        => 1,
                 'fornotfirst'     => 1,
                 'fornotlast'      => 1,
                 'forlast'         => 1,
                 'endfor'          => 1,
                 'comment'         => 1,
                 'flag_overrides'  => 1,
                 'marker'          => 1,
                 'uc'              => 1,
                 'lc'              => 1,
                 'ucw'             => 1,
                 'normalize'       => 1,
                );

my(%filecache) = ();

# ************************************************************
# Subroutine Section
# ************************************************************

sub new {
  my($class) = shift;
  my($prjc)  = shift;
  my($self)  = $class->SUPER::new();

  $self->{'prjc'}       = $prjc;
  $self->{'ti'}         = $prjc->get_template_input();
  $self->{'cslashes'}   = $prjc->convert_slashes();
  $self->{'crlf'}       = $prjc->crlf();
  $self->{'clen'}       = length($self->{'crlf'});
  $self->{'values'}     = {};
  $self->{'defaults'}   = {};
  $self->{'lines'}      = [];
  $self->{'built'}      = '';
  $self->{'sstack'}     = [];
  $self->{'lstack'}     = [];
  $self->{'if_skip'}    = 0;
  $self->{'parameters'} = [];

  $self->{'foreach'}  = {};
  $self->{'foreach'}->{'count'}      = -1;
  $self->{'foreach'}->{'nested'}     = 0;
  $self->{'foreach'}->{'name'}       = [];
  $self->{'foreach'}->{'names'}      = [];
  $self->{'foreach'}->{'text'}       = [];
  $self->{'foreach'}->{'scope'}      = [];
  $self->{'foreach'}->{'temp_scope'} = [];
  $self->{'foreach'}->{'processing'} = 0;

  return $self;
}


sub basename {
  my($self) = shift;
  my($file) = shift;

  if ($file =~ s/.*[\/\\]//) {
    $self->{'values'}->{'basename_found'} = 1;
  }
  else {
    delete $self->{'values'}->{'basename_found'};
  }
  return $file;
}


sub dirname {
  my($self) = shift;
  my($file) = shift;
  for(my $i = length($file) - 1; $i != 0; --$i) {
    my($ch) = substr($file, $i, 1);
    if ($ch eq '/' || $ch eq '\\') {
      ## The template file may use this value (<%dirname_found%>)
      ## to determine whether a dirname removed the basename or not
      $self->{'values'}->{'dirname_found'} = 1;
      return substr($file, 0, $i);
    }
  }
  delete $self->{'values'}->{'dirname_found'};
  return '.';
}


sub strip_line {
  #my($self) = shift;
  #my($line) = shift;

  ## Override strip_line() from Parser.
  ## We need to preserve leading space and
  ## there is no comment string in templates.
  ++$_[0]->{'line_number'};
  $_[1] =~ s/\s+$//;

  return $_[1];
}


## Append the current value to the line that is being
## built.  This line may be a foreach line or a general
## line without a foreach.
sub append_current {
  my($self)  = shift;
  my($value) = shift;

  if ($self->{'foreach'}->{'count'} >= 0) {
    $self->{'foreach'}->{'text'}->[$self->{'foreach'}->{'count'}] .= $value;
  }
  else {
    $self->{'built'} .= $value;
  }
}


sub set_current_values {
  my($self) = shift;
  my($name) = shift;
  my($set)  = 0;

  ## If any value within a foreach matches the name
  ## of a hash table within the template input we will
  ## set the values of that hash table in the current scope
  if (defined $self->{'ti'}) {
    my($counter) = $self->{'foreach'}->{'count'};
    if ($counter >= 0) {
      my($value) = $self->{'ti'}->get_value($name);
      if (defined $value && UNIVERSAL::isa($value, 'HASH')) {
        my(%copy) = ();
        foreach my $key (keys %$value) {
          $copy{$key} = $self->{'prjc'}->adjust_value($key, $$value{$key});
        }
        $self->{'foreach'}->{'temp_scope'}->[$counter] = \%copy;
        $set = 1;
      }
    }
  }
  return $set;
}


sub get_nested_value {
  my($self)  = shift;
  my($name)  = shift;
  my($value) = undef;

  if ($name =~ /^(.*)\->(\w+)/) {
    my($pre)  = $1;
    my($post) = $2;
    my($base) = $self->get_value($pre);
    if (defined $base) {
      $value = $self->{'prjc'}->get_special_value($pre, $post, $base,
                                                  @{$self->{'parameters'}});
    }
  }

  return $value;
}


sub get_value {
  my($self)    = shift;
  my($name)    = shift;
  my($value)   = undef;
  my($counter) = $self->{'foreach'}->{'count'};

  ## First, check the temporary scope (set inside a foreach)
  if ($counter >= 0) {
    while(!defined $value && $counter >= 0) {
      $value = $self->{'foreach'}->{'temp_scope'}->[$counter]->{$name};
      --$counter;
    }
    $counter = $self->{'foreach'}->{'count'};
  }

  if (!defined $value) {
    ## Next, check for a template value
    if (defined $self->{'ti'}) {
      $value = $self->{'ti'}->get_value($name);
      if (defined $value) {
        $value = $self->{'prjc'}->adjust_value($name, $value);
      }
      else {
        my($uvalue) = $self->{'prjc'}->adjust_value($name, []);
        if (defined $$uvalue[0]) {
          $value = $uvalue;
        }
      }
    }

    if (!defined $value) {
      ## Next, check the inner to outer foreach
      ## scopes for overriding values
      while(!defined $value && $counter >= 0) {
        $value = $self->{'foreach'}->{'scope'}->[$counter]->{$name};
        --$counter;
      }

      ## Then get the value from the project creator
      if (!defined $value) {
        $value = $self->{'prjc'}->get_assignment($name);

        ## Then get it from our known values
        if (!defined $value) {
          $value = $self->{'values'}->{$name};
          if (!defined $value) {
            ## Call back onto the project creator to allow
            ## it to fill in the value before defaulting to undef.
            $value = $self->{'prjc'}->fill_value($name);
            if (!defined $value && $name =~ /\->/) {
              $value = $self->get_nested_value($name);
            }
          }
        }
      }
    }
  }

  return $self->{'prjc'}->relative($value);
}


sub get_value_with_default {
  my($self)  = shift;
  my($name)  = shift;
  my($value) = $self->get_value($name);

  if (!defined $value) {
    $value = $self->{'defaults'}->{$name};
    if (defined $value) {
      $value = $self->{'prjc'}->relative(
                       $self->{'prjc'}->adjust_value($name, $value));
    }
    else {
      #$self->warning("$name defaulting to empty string.");
      $value = '';
    }
  }

  if (UNIVERSAL::isa($value, 'ARRAY')) {
    $value = "@$value";
  }

  return $value;
}


sub process_foreach {
  my($self)   = shift;
  my($index)  = $self->{'foreach'}->{'count'};
  my($text)   = $self->{'foreach'}->{'text'}->[$index];
  my($status) = 1;
  my($error)  = undef;
  my(@values) = ();
  my($names)  = $self->create_array($self->{'foreach'}->{'names'}->[$index]);
  my($name)   = $self->{'foreach'}->{'name'}->[$index];

  ## Get the values for all of the variable names
  ## contained within the foreach
  foreach my $n (@$names) {
    my($vals) = $self->get_value($n);
    if (defined $vals && $vals ne '') {
      if (!UNIVERSAL::isa($vals, 'ARRAY')) {
        $vals = $self->create_array($vals);
      }
      push(@values, @$vals);
    }
    if (!defined $name) {
      $name = $n;
      $name =~ s/s$//;
    }
  }

  ## Reset the text (it will be regenerated by calling parse_line
  $self->{'foreach'}->{'text'}->[$index] = '';

  if (defined $values[0]) {
    my($scope) = $self->{'foreach'}->{'scope'}->[$index];

    $$scope{'forlast'}     = '';
    $$scope{'fornotlast'}  = 1;
    $$scope{'forfirst'}    = 1;
    $$scope{'fornotfirst'} = '';

    ## If the foreach values are mixed (HASH and SCALAR), then
    ## remove the SCALAR values.
    my($pset) = undef;
    for(my $i = 0; $i <= $#values; ++$i) {
      my($set) = $self->set_current_values($values[$i]);
      if (!defined $pset) {
        $pset |= $set;
      }
      else {
        if ($pset && !$set) {
          splice(@values, $i, 1);
          $i = 0;
          $pset = undef;
        }
      }
    }

    for(my $i = 0; $i <= $#values; ++$i) {
      my($value) = $values[$i];

      ## Set the corresponding values in the temporary scope
      $self->set_current_values($value);

      ## Set the special values that only exist
      ## within a foreach
      if ($i != 0) {
        $$scope{'forfirst'}    = '';
        $$scope{'fornotfirst'} = 1;
      }
      if ($i == $#values) {
        $$scope{'forlast'}    = 1;
        $$scope{'fornotlast'} = '';
      }
      $$scope{'forcount'} = $i + 1;

      ## We don't use adjust_value here because these names
      ## are generated from a foreach and should not be adjusted.
      $$scope{$name} = $value;

      ## A tiny hack for VC7
      if ($name eq 'configuration') {
        $self->{'prjc'}->update_project_info($self, 1,
                                             ['configuration', 'platform'],
                                             '|');
      }

      ## Now parse the line of text, each time
      ## with different values
      ++$self->{'foreach'}->{'processing'};
      ($status, $error) = $self->parse_line(undef, $text);
      --$self->{'foreach'}->{'processing'};
      if (!$status) {
        last;
      }
    }
  }

  return $status, $error;
}


sub handle_endif {
  my($self) = shift;
  my($name) = shift;
  my($end)  = pop(@{$self->{'sstack'}});
  pop(@{$self->{'lstack'}});

  if (!defined $end) {
    return 0, "Unmatched $name";
  }
  else {
    my($in) = index($end, $name);
    if ($in == 0) {
      $self->{'if_skip'} = 0;
    }
    elsif ($in == -1) {
      return 0, "Unmatched $name";
    }
  }

  return 1, undef;
}


sub handle_endfor {
  my($self) = shift;
  my($name) = shift;
  my($end)  = pop(@{$self->{'sstack'}});
  pop(@{$self->{'lstack'}});

  if (!defined $end) {
    return 0, "Unmatched $name";
  }
  else {
    my($in) = index($end, $name);
    if ($in == 0) {
      my($index) = $self->{'foreach'}->{'count'};
      my($status, $error) = $self->process_foreach();
      if ($status) {
        --$self->{'foreach'}->{'count'};
        $self->append_current($self->{'foreach'}->{'text'}->[$index]);
      }
      return $status, $error;
    }
    elsif ($in == -1) {
      return 0, "Unmatched $name";
    }
  }

  return 1, undef;
}


sub get_flag_overrides {
  my($self)  = shift;
  my($name)  = shift;
  my($type)  = shift;
  my($value) = undef;
  my($file)  = $self->get_value($name);
  my($prjc)  = $self->{'prjc'};
  my($fo)    = $prjc->{'flag_overrides'};

  if (defined $file) {
    ## Replace the custom_type key with the actual custom type
    if ($name =~ /^custom_type\->/) {
      my($ct) = $self->get_value('custom_type');
      if (defined $ct) {
        $name = $ct;
      }
    }

    foreach my $key (keys %$fo) {
      if ($key =~ /^$name/) {
        foreach my $of (keys %{$$fo{$key}}) {
          my($cv) = $of;
          if ($self->{'cslashes'}) {
            $cv = $prjc->slash_to_backslash($of);
          }
          if ($cv eq $file) {
            foreach my $ma (keys %{$prjc->{'matching_assignments'}}) {
              if ($ma eq $key) {
                foreach my $aname (@{$prjc->{'matching_assignments'}->{$ma}}) {
                  if ($aname eq $type &&
                      defined $$fo{$key}->{$of}->{$aname}) {
                    $value = $$fo{$key}->{$of}->{$aname};
                    last;
                  }
                }
                last;
              }
            }
            last;
          }
        }
        last;
      }
    }
  }

  return $prjc->relative($value);
}


sub process_compound_if {
  my($self)   = shift;
  my($str)    = shift;
  my($status) = 0;

  if ($str =~ /\|\|/) {
    my($ret) = 0;
    foreach my $v (split(/\s*\|\|\s*/, $str)) {
      $ret |= $self->process_compound_if($v);
      if ($ret != 0) {
        return 1;
      }
    }
  }
  elsif ($str =~ /\&\&/) {
    my($ret) = 1;
    foreach my $v (split(/\s*\&\&\s*/, $str)) {
      $ret &&= $self->process_compound_if($v);
      if ($ret == 0) {
        return 0;
      }
    }
    $status = 1;
  }
  else {
    ## See if we need to reverse the return value
    my($not) = 0;
    if ($str =~ /^!(.*)/) {
      $not = 1;
      $str = $1;
    }

    ## Get the value based on the string
    my($val) = ($str =~ /flag_overrides\(([^\)]+),\s*([^\)]+)\)/ ?
                               $self->get_flag_overrides($1, $2) :
                               $self->get_value($str));

    ## See if any portion of the value is defined and not empty
    my($ret) = 0;
    if (defined $val) {
      if (UNIVERSAL::isa($val, 'ARRAY')) {
        foreach my $v (@$val) {
          if ($v ne '') {
            $ret = 1;
            last;
          }
        }
      }
      elsif ($val ne '') {
        $ret = 1;
      }
    }
    return ($not ? !$ret : $ret);
  }

  return $status;
}


sub handle_if {
  my($self)   = shift;
  my($val)    = shift;
  my($name)   = 'endif';

  push(@{$self->{'lstack'}}, $self->get_line_number() . " $val");
  if ($self->{'if_skip'}) {
    push(@{$self->{'sstack'}}, "*$name");
  }
  else {
    ## Determine if we are skipping the portion of this if statement
    ## $val will always be defined since we won't get into this method
    ## without properly parsing the if statement.
    $self->{'if_skip'} = !$self->process_compound_if($val);
    push(@{$self->{'sstack'}}, $name);
  }
}


sub handle_else {
  my($self)  = shift;
  my(@scopy) = @{$self->{'sstack'}};

  ## This method does not take into account that
  ## multiple else clauses could be supplied to a single if.
  ## Someday, this may be fixed.
  if (defined $scopy[$#scopy] && $scopy[$#scopy] eq 'endif') {
    $self->{'if_skip'} ^= 1;
  }
}


sub handle_foreach {
  my($self)        = shift;
  my($val)         = shift;
  my($name)        = 'endfor';
  my($status)      = 1;
  my($errorString) = undef;

  push(@{$self->{'lstack'}}, $self->get_line_number());
  if (!$self->{'if_skip'}) {
    my($vname) = undef;
    if ($val =~ /([^,]+),(.*)/) {
      $vname = $1;
      $val   = $2;
      $vname =~ s/^\s+//;
      $vname =~ s/\s+$//;
      $val   =~ s/^\s+//;
      $val   =~ s/\s+$//;

      ## Due to the way flag_overrides works, we can't allow
      ## the user to name the foreach variable when dealing
      ## with custom types.
      if ($val =~ /^custom_type\->/ || $val eq 'custom_types') {
        $status = 0;
        $errorString = 'The foreach variable can not be ' .
                       'named when dealing with custom types';
      }
      elsif ($val =~ /^grouped_.*_file\->/ || $val =~ /^grouped_.*files$/) {
        $status = 0;
        $errorString = 'The foreach variable can not be ' .
                       'named when dealing with grouped files';
      }
    }

    push(@{$self->{'sstack'}}, $name);
    ++$self->{'foreach'}->{'count'};

    my($index) = $self->{'foreach'}->{'count'};
    $self->{'foreach'}->{'name'}->[$index]  = $vname;
    $self->{'foreach'}->{'names'}->[$index] = $val;
    $self->{'foreach'}->{'text'}->[$index]  = '';
    $self->{'foreach'}->{'scope'}->[$index] = {};
  }
  else {
    push(@{$self->{'sstack'}}, "*$name");
  }

  return $status, $errorString;
}


sub handle_special {
  my($self) = shift;
  my($name) = shift;
  my($val)  = shift;

  ## If $name (fornotlast, forfirst, etc.) is set to 1
  ## Then we append the $val onto the current string that's
  ## being built.
  if ($self->get_value($name)) {
    $self->append_current($val);
  }
}


sub handle_uc {
  my($self) = shift;
  my($name) = shift;

  $self->append_current(uc($self->get_value_with_default($name)));
}


sub handle_lc {
  my($self) = shift;
  my($name) = shift;

  $self->append_current(lc($self->get_value_with_default($name)));
}


sub handle_ucw {
  my($self) = shift;
  my($name) = shift;
  my($val)  = $self->get_value_with_default($name);

  substr($val, 0, 1) = uc(substr($val, 0, 1));
  while($val =~ /[_\s]([a-z])/) {
    my($uc) = uc($1);
    $val =~ s/[_\s][a-z]/ $uc/;
  }
  $self->append_current($val);
}


sub handle_normalize {
  my($self) = shift;
  my($name) = shift;
  my($val)  = $self->get_value_with_default($name);

  $val =~ tr/\-/_/;
  $self->append_current($val);
}


sub handle_noextension {
  my($self) = shift;
  my($name) = shift;
  my($val)  = $self->get_value_with_default($name);

  $val =~ s/\.[^\.]+$//;
  $self->append_current($val);
}


sub handle_dirname {
  my($self) = shift;
  my($name) = shift;

  if (!$self->{'if_skip'}) {
    $self->append_current(
              $self->dirname($self->get_value_with_default($name)));
  }
}


sub handle_basename {
  my($self) = shift;
  my($name) = shift;

  if (!$self->{'if_skip'}) {
    $self->append_current(
              $self->basename($self->get_value_with_default($name)));
  }
}


sub handle_basenoextension {
  my($self) = shift;
  my($name) = shift;
  my($val)  = $self->basename($self->get_value_with_default($name));

  $val =~ s/\.[^\.]+$//;
  $self->append_current($val);
}


sub handle_flag_overrides {
  my($self) = shift;
  my($name) = shift;
  my($type) = '';

  ($name, $type) = split(/,\s*/, $name);

  my($value) = $self->get_flag_overrides($name, $type);
  if (defined $value) {
    $self->append_current($value);
  }
}


sub handle_marker {
  my($self) = shift;
  my($name) = shift;
  my($val)  = $self->{'prjc'}->get_verbatim($name);

  if (defined $val) {
    $self->append_current($val);
  }
}


sub handle_function {
  my($self)   = shift;
  my($name)   = shift;
  my($prefix) = shift;
  my($input)  = $self->get_value($prefix . '->input_file');
  my($output) = undef;

  if (defined $input) {
    if ($self->{'cslashes'}) {
      $input = $self->{'prjc'}->slash_to_backslash($input);
    }
    $output = $self->get_value($prefix . '->input_file->output_file');

    if (defined $output) {
      my($fo) = $self->get_flag_overrides($prefix . '->input_file',
                                          'gendir');
      if (defined $fo) {
        $output = $fo . '/' . File::Basename::basename($output);
      }
      if ($self->{'cslashes'}) {
        $output = $self->{'prjc'}->slash_to_backslash($output);
      }
    }
  }

  ## Set the parameters array with the determined input and output files
  $self->{'parameters'} = [ $input, $output ];

  ## Append the value returned by get_value_with_default.  It will use
  ## the parameters when it calls get_special_value on the ProjectCreator
  $self->append_current($self->get_value_with_default($name));

  ## Reset the parameters arary
  $self->{'parameters'} = [];
}


sub process_name {
  my($self)        = shift;
  my($line)        = shift;
  my($length)      = 0;
  my($status)      = 1;
  my($errorString) = undef;

  if ($line eq '') {
  }
  elsif ($line =~ /^(\w+)(\(([^\)]+|\".*\"|flag_overrides\([^\)]+,\s*[^\)]+\))\)|\->\w+([\w\-\>]+)?)?%>/) {
    ## Split the line into a name and value
    my($name, $val) = ();
    if ($line =~ /([^%\(]+)(\(([^%]+)\))?%>/) {
      $name = lc($1);
      $val  = $3;
    }

    $length += length($name);
    if (defined $val) {
      ## Add the length of the value plus 2 for the surrounding ()
      $length += length($val) + 2;
    }

    if (defined $keywords{$name}) {
      if ($name eq 'endif') {
        ($status, $errorString) = $self->handle_endif($name);
      }
      elsif ($name eq 'if') {
        $self->handle_if($val);
      }
      elsif ($name eq 'endfor') {
        ($status, $errorString) = $self->handle_endfor($name);
      }
      elsif ($name eq 'foreach') {
        ($status, $errorString) = $self->handle_foreach($val);
      }
      elsif ($name eq 'fornotlast'  || $name eq 'forlast' ||
             $name eq 'fornotfirst' || $name eq 'forfirst') {
        if (!$self->{'if_skip'}) {
          $self->handle_special($name, $self->process_special($val));
        }
      }
      elsif ($name eq 'else') {
        $self->handle_else();
      }
      elsif ($name eq 'flag_overrides') {
        if (!$self->{'if_skip'}) {
          $self->handle_flag_overrides($val);
        }
      }
      elsif ($name eq 'noextension') {
        if (!$self->{'if_skip'}) {
          $self->handle_noextension($val);
        }
      }
      elsif ($name eq 'basenoextension') {
        if (!$self->{'if_skip'}) {
          $self->handle_basenoextension($val);
        }
      }
      elsif ($name eq 'basename') {
        if (!$self->{'if_skip'}) {
          $self->handle_basename($val);
        }
      }
      elsif ($name eq 'marker') {
        if (!$self->{'if_skip'}) {
          $self->handle_marker($val);
        }
      }
      elsif ($name eq 'dirname') {
        if (!$self->{'if_skip'}) {
          $self->handle_dirname($val);
        }
      }
      elsif ($name eq 'comment') {
        ## Ignore the contents of the comment
      }
      elsif ($name eq 'uc') {
        if (!$self->{'if_skip'}) {
          $self->handle_uc($val);
        }
      }
      elsif ($name eq 'ucw') {
        if (!$self->{'if_skip'}) {
          $self->handle_ucw($val);
        }
      }
      elsif ($name eq 'lc') {
        if (!$self->{'if_skip'}) {
          $self->handle_lc($val);
        }
      }
      elsif ($name eq 'normalize') {
        if (!$self->{'if_skip'}) {
          $self->handle_normalize($val);
        }
      }
    }
    else {
      if (!$self->{'if_skip'}) {
        if (defined $val && !defined $self->{'defaults'}->{$name}) {
          $self->{'defaults'}->{$name} = $self->process_special($val);
        }
        $self->append_current($self->get_value_with_default($name));
      }
    }
  }
  elsif ($line =~ /^((\w+)(->\w+)+)\(\)%>/) {
    my($name) = $1;
    ## Handle all "function calls" separately
    if (!$self->{'if_skip'}) {
      $self->handle_function($name, $2);
    }
    $length += length($name) + 2;
  }
  else {
    my($error)  = $line;
    my($length) = length($line);
    for(my $i = 0; $i < $length; ++$i) {
      my($part) = substr($line, $i, 2);
      if ($part eq '%>') {
        $error = substr($line, 0, $i + 2);
        last;
      }
    }
    $status = 0;
    $errorString = "Unable to parse line starting at $error";
  }

  return $status, $errorString, $length;
}


sub collect_data {
  my($self)  = shift;
  my($prjc)  = $self->{'prjc'};
  my($cwd)   = $self->getcwd();
  my($relwd) = $prjc->reverse_relative($cwd);

  ## Set the current working directory
  if ($self->{'cslashes'}) {
    $cwd = $prjc->slash_to_backslash($cwd);
  }
  $self->{'values'}->{'cwd'} = $cwd;

  ## Set the relative working directory
  $relwd =~ s/\$\([^\)]+\)[\/\\]//;
  if ($self->{'cslashes'}) {
    $relwd = $prjc->slash_to_backslash($relwd);
  }
  $self->{'values'}->{'relwd'} = $relwd;

  ## Collect the components into {'values'} somehow
  foreach my $key (keys %{$prjc->{'valid_components'}}) {
    my(@list) = $prjc->get_component_list($key);
    if (defined $list[0]) {
      $self->{'values'}->{$key} = \@list;
    }
  }

  ## A tiny hack (mainly for VC6 projects)
  ## for the workspace creator.  It needs to know the
  ## target names to match up with the project name.
  $prjc->update_project_info($self, 0, ['project_name']);

  ## This is for all projects
  $prjc->update_project_info($self, 1, ['after']);

  ## VC7 Projects need to know the GUID.
  ## We need to save this value in our known values
  ## since each guid generated will be different.  We need
  ## this to correspond to the same guid used in the workspace.
  my($guid) = $prjc->update_project_info($self, 1, ['guid']);
  $self->{'values'}->{'guid'} = $guid;
}


sub parse_line {
  my($self)        = shift;
  my($ih)          = shift;
  my($line)        = shift;
  my($status)      = 1;
  my($errorString) = undef;
  my($length)      = length($line);
  my($name)        = 0;
  my($startempty)  = ($length == 0 ? 1 : 0);
  my($append_name) = 0;

  ## If processing a foreach or the line only
  ## contains a keyword, then we do
  ## not need to add a newline to the end.
  if ($self->{'foreach'}->{'processing'} == 0) {
    my($is_only_keyword) = undef;
    if ($line =~ /^\s*<%(\w+)(\([^\)]+\))?%>$/) {
      $is_only_keyword = defined $keywords{$1};
    }

    if (!$is_only_keyword) {
      $line   .= $self->{'crlf'};
      $length += $self->{'clen'};
    }
  }

  if ($self->{'foreach'}->{'count'} < 0) {
    $self->{'built'} = '';
  }

  for(my $i = 0; $i < $length; ++$i) {
    my($part) = substr($line, $i, 2);
    if ($part eq '<%') {
      ++$i;
      $name = 1;
    }
    elsif ($part eq '%>') {
      ++$i;
      $name = 0;
      if ($append_name) {
        $append_name = 0;
        if (!$self->{'if_skip'}) {
          $self->append_current($part);
        }
      }
    }
    elsif ($name) {
      my($substr)  = substr($line, $i);
      my($efcheck) = ($substr =~ /^endfor\%\>/);
      my($focheck) = ($efcheck ? 0 : ($substr =~ /^foreach\(/));

      if ($focheck && $self->{'foreach'}->{'count'} >= 0) {
        ++$self->{'foreach'}->{'nested'};
      }

      if ($self->{'foreach'}->{'count'} < 0 ||
          $self->{'foreach'}->{'processing'} > $self->{'foreach'}->{'nested'} ||
          (($efcheck || $focheck) &&
           $self->{'foreach'}->{'nested'} == $self->{'foreach'}->{'processing'})) {
        my($nlen) = 0;
        ($status,
         $errorString,
         $nlen) = $self->process_name($substr);

        if ($status && $nlen == 0) {
          $errorString = "Could not parse this line at column $i";
          $status = 0;
        }
        if (!$status) {
          last;
        }

        $i += ($nlen - 1);
      }
      else  {
        $name = 0;
        if (!$self->{'if_skip'}) {
          $self->append_current('<%' . substr($line, $i, 1));
          $append_name = 1;
        }
      }

      if ($efcheck && $self->{'foreach'}->{'nested'} > 0) {
        --$self->{'foreach'}->{'nested'};
      }
    }
    else {
      if (!$self->{'if_skip'}) {
        $self->append_current(substr($line, $i, 1));
      }
    }
  }

  if ($self->{'foreach'}->{'count'} < 0) {
    ## If the line started out empty and we're not
    ## skipping from the start or the built up line is not empty
    if ($startempty ||
        ($self->{'built'} ne $self->{'crlf'} && $self->{'built'} ne '')) {
      push(@{$self->{'lines'}}, $self->{'built'});
    }
  }

  return $status, $errorString;
}


sub parse_file {
  my($self)  = shift;
  my($input) = shift;

  $self->collect_data();
  my($status, $errorString) = $self->cached_file_read($input);

  if ($status) {
    my($sstack) = $self->{'sstack'};
    if (defined $$sstack[0]) {
      my($lstack) = $self->{'lstack'};
      $status = 0;
      $errorString = "Missing an $$sstack[0] starting at $$lstack[0]";
    }
  }

  if (!$status) {
    my($linenumber) = $self->get_line_number();
    $errorString = "$input: line $linenumber:\n$errorString";
  }

  return $status, $errorString;
}


sub get_lines {
  my($self) = shift;
  return $self->{'lines'};
}


sub get_cache {
  my($self) = shift;
  my($key)  = shift;
  return $filecache{$key};
}


sub cache_line {
  my($self) = shift;
  my($key)  = shift;
  my($line) = shift;

  ## If we don't have an array for this key, then start one
  if (!defined $filecache{$key}) {
    $filecache{$key} = [];
  }

  ## Push the line onto the array for this key
  push(@{$filecache{$key}}, $line);
}


1;
