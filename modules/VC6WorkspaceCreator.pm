package VC6WorkspaceCreator;

# ************************************************************
# Description   : A VC6 Workspace Creator
# Author        : Chad Elliott
# Create Date   : 5/13/2002
# ************************************************************

# ************************************************************
# Pragmas
# ************************************************************

use strict;

use VC6ProjectCreator;
use WinWorkspaceBase;
use WorkspaceCreator;
use VCPropertyBase;

use vars qw(@ISA);
@ISA = qw(VCPropertyBase WinWorkspaceBase WorkspaceCreator);

# ************************************************************
# Subroutine Section
# ************************************************************


sub compare_output {
  #my $self = shift;
  return 1;
}


sub workspace_file_extension {
  #my $self = shift;
  return '.dsw';
}


sub pre_workspace {
  my($self, $fh) = @_;
  my $crlf = $self->crlf();

  ## This identifies it as a Visual C++ file
  print $fh 'Microsoft Developer Studio Workspace File, Format Version 6.00', $crlf;

  ## Optionally print the workspace comment
  $self->print_workspace_comment($fh,
            '#', $crlf,
            '# $Id$', $crlf,
            '#', $crlf,
            '# This file was generated by MPC.  Any changes made directly to', $crlf,
            '# this file will be lost the next time it is generated.', $crlf,
            '#', $crlf,
            '# MPC Command:', $crlf,
            '# ', $self->create_command_line_string($0, @ARGV), $crlf, $crlf);
}


sub write_comps {
  my($self, $fh, $gen) = @_;
  my $projects = $self->get_projects();
  my $pjs = $self->get_project_info();
  my $crlf = $self->crlf();

  ## Sort the project so that they resulting file can be exactly
  ## reproduced given the same list of projects.
  foreach my $project (sort { $gen->file_sorter($a, $b) } @$projects) {

    ## Add the project name and project file information
    print $fh "###############################################################################$crlf$crlf",
              'Project: "', $$pjs{$project}->[ProjectCreator::PROJECT_NAME],
              '"=', $self->slash_to_backslash($project),
              " - Package Owner=<4>$crlf$crlf",
              "Package=<5>$crlf", '{{{', $crlf, "}}}$crlf$crlf",
              "Package=<4>$crlf", '{{{', $crlf;

    my $deps = $self->get_validated_ordering($project);
    if (defined $$deps[0]) {
      ## Add in the project dependencies
      foreach my $dep (@$deps) {
        print $fh "    Begin Project Dependency$crlf",
                  "    Project_Dep_Name $dep$crlf",
                  "    End Project Dependency$crlf";
      }
    }

    ## End the project section
    print $fh "}}}$crlf$crlf";
  }
}


sub post_workspace {
  my($self, $fh) = @_;
  my $crlf = $self->crlf();

  ## This text is always the same
  print $fh "###############################################################################$crlf$crlf",
            "Global:$crlf$crlf",
            "Package=<5>$crlf", '{{{', "$crlf}}}$crlf$crlf",
            "Package=<3>$crlf", '{{{', "$crlf}}}$crlf$crlf",
            "###############################################################################$crlf$crlf";
}


1;
