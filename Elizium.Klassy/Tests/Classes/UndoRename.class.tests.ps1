Import-Module .\Output\Elizium.Klassy\Elizium.Klassy.psm1

Describe 'UndoRename' {
  BeforeEach {
    InModuleScope Elizium.Klassy {
      [string]$script:_path = "$TestDrive\undo-script.ps1";
      [PoShShell]$script:_shell = [PoShShell]::new($_path);
      [Undo]$script:_undoRename = [UndoRename]::new($_shell);
    }
  }

  AfterEach {
    InModuleScope Elizium.Klassy {
      if (Test-Path -LiteralPath $_path) {
        Remove-Item -LiteralPath $_path;
      }
    }
  }

  Context 'given: PoShShell' {
    It 'should: generate undo rename operations' {
      InModuleScope Elizium.Klassy {
        [PSCustomObject[]]$operations = @(
          [PSCustomObject]@{
            Directory = "$TestDrive";
            From = "one-old.txt";
            To   = 'one-new.txt';
          },

          [PSCustomObject]@{
            Directory = "$TestDrive";
            From = "two-old.txt";
            To   = 'two-new.txt';
          },

          [PSCustomObject]@{
            Directory = "$TestDrive";
            From = "three-old.txt";
            To   = 'three-new.txt';
          }
        )

        $operations | ForEach-Object {
          $_undoRename.alert($_);
        }

        [string]$content = $_undoRename.generate();
        $content | Should -Match "one-old\.txt";
        $content | Should -Match "two-old\.txt";
        $content | Should -Match "three-old\.txt";
        $content | Should -Match "one-new\.txt";
        $content | Should -Match "two-new\.txt";
        $content | Should -Match "three-new\.txt";
      }
    }
  }
}
