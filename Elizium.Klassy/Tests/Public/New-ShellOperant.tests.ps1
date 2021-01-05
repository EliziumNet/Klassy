Import-Module .\Output\Elizium.Klassy\Elizium.Klassy.psm1
Describe 'New-ShellOperant' {
  BeforeEach {
    InModuleScope Elizium.Klassy {
      Mock -ModuleName Elizium.Klassy get-CurrentTime {
        return '04-Jan-2021';
      }
    }
  }

  Context 'given: invoked with defaults' {
    It 'should: return UndoRename instance' {
      InModuleScope Elizium.Klassy {
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
      InModuleScope Elizium.Klassy {
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
