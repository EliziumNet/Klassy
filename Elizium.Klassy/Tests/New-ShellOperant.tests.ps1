Import-Module .\Output\Elizium.Shelly\Elizium.Shelly.psm1
Describe 'New-ShellOperant' {
  BeforeEach {
    InModuleScope Elizium.Shelly {
      Mock -ModuleName Elizium.Shelly get-CurrentTime {
        return '04-Jan-2021';
      }
    }
  }

  Context 'given: invoked with defaults' {
    It 'should: return UndoRename instance' {
      InModuleScope Elizium.Shelly {
        [UndoRename]$operant = New-ShellOperant -BaseFilename 'undo-rename' `
          -Directory $TestDrive;

        $operant | Should -Not -BeNullOrEmpty;
        $operant.GetType() | Should -Be UndoRename;

        [string]$fullPath = $operant.Shell.FullPath;
        $fullPath | Should -Match '04-Jan-2021';
      }
    }
  }

  Context 'given: invoked explicitly with UndoRename and PoShShell' {
    It 'should: return UndoRename instance' {
      InModuleScope Elizium.Shelly {
        [UndoRename]$operant = New-ShellOperant -BaseFilename 'undo-rename' `
          -Directory $TestDrive -Operant 'UndoRename' -Shell 'PoShShell';

        $operant | Should -Not -BeNullOrEmpty;
        $operant.GetType() | Should -Be UndoRename;

        [string]$fullPath = $operant.Shell.FullPath;
        $fullPath | Should -Match '04-Jan-2021';
      }
    }
  }
}
