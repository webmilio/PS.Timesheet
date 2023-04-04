using namespace System.Collections.Generic
using namespace System.Management.Automation.Host

# Settings
$LogsDirectory = 'logs'
$ActivitiesDirectory = 'activities'
$TimeDisplayFormat = "HH:mm:ss"

# Default choices
$breakChoice = [ChoiceDescription]::new("Brea&k", "Go on a break!")
$exitChoice = [ChoiceDescription]::new("&Exit", "End your timesheet")

# Choice bindings
$choiceBindings = [Dictionary[ChoiceDescription, System.Action]]::new()
$choiceBindings.Add($breakChoice, $function:TakeBreak)
$choiceBindings.Add($exitChoice, $function:End)

#region Script
$script:labels = $null
$script:doing = $null

$script:decisionIndex = $null
$script:decision = $null

$script:startTime = $null
$script:running = $true


#region Choice Functions
function End { 
    EndSplit

    $script:running = $false 
}

function TakeBreak {
    Write-Host 'Taking a break!'

    EndSplit
}

function BeginSplit {
    $script:startTime = [datetime]::Now
    
    Write-Host "Started working on $(GetDecisionName)"
}

function EndSplit {    
    $workTime = [datetime]::Now - $script:startTime
    Write-Host "Split ended for $(GetDecisionName) $($workTime.Hours) hour(s), $($workTime.Minutes) minute(s)"
}

function GetDecisionName() {
    return $script:labels[$decisionIndex]
}
#endregion

$logs = New-Item $LogsDirectory -ItemType Directory -ErrorAction Ignore

if ($null -eq $logs)
{
    $logs = Get-Item $LogsDirectory
}

$activityFiles = Get-ChildItem "$ActivitiesDirectory\*" | Sort-Object Name
$choices = [ChoiceDescription[]]::new($activityFiles.Count + 2)

$script:labels = [string[]]::new($choices.Length)

$choices[$choices.Length - 2] = $breakChoice
$choices[$choices.Length - 1] = $exitChoice

for ($i = 0; $i -lt $activityFiles.Length; $i++)
{
    $lines = Get-Content $activityFiles[$i]
    $choices[$i] = [ChoiceDescription]::new($lines[0], ($lines[1..($lines.Length - 1)] -join [System.Environment]::NewLine))
}

for ($i = 0; $i -lt $script:choiceLabels.Count; $i++) 
{
    $script:choiceLabels[$i] = $choices[$i].Replace("&", [string]::Empty)
}

Write-Host "Starting timesheet at $($timeNow.ToString($TimeDisplayFormat))"

$entryName = $timeNow.ToString("yyyyMMdd")

do
{
    $script:decisionIndex = $Host.UI.PromptForChoice("Which activity are you doing?", $null, $choices, 0)
    $script:decision = $choices[$decisionIndex]

    if ($choiceBindings.ContainsKey($decision))
    {
        $choiceBindings[$decision].Invoke()
    }
    else
    {
        BeginSplit
    }

    $doing = $decision
} 
while ($script:running)
