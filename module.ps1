$module = "automation"
Remove-Module $module -ErrorAction SilentlyContinue
Import-Module "./$module" -Force

$commands = (Get-Command -Module $module -CommandType Function).Name -join ", "
Write-Host "Automation module loaded. Available commands: $commands"