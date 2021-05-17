
function New-ChangeLogOptionsManager {
  param(
    [PSCustomObject]$OptionsInfo
  )

  [ChangeLogOptionsManager]$manager = [ChangeLogOptionsManager]::new($OptionsInfo);
  $manager.Init();

  return $manager;
}
