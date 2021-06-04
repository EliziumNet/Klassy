
function New-PoShLogOptionsManager {
  param(
    [PSCustomObject]$OptionsInfo
  )

  [PoShLogOptionsManager]$manager = [PoShLogOptionsManager]::new($OptionsInfo);
  $manager.Init();

  return $manager;
}
