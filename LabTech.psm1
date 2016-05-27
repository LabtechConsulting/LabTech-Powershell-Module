<#
.SYNOPSIS
    This is a PowerShell Module for LabTech.
    labtechconsulting.com
    labtechsoftware.com
    msdn.microsoft.com/powershell


.DESCRIPTION
    This is a set of commandlets to interface with the LabTech Agent v10.5

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
  
#>

#requires -version 3

#Module Version
$ModuleVersion = "1.0"
 
#region-[Functions]------------------------------------------------------------

Function Get-LTServiceInfo{ 
<#
.SYNOPSIS
    This function will pull all of the registy data into an object.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 
    [CmdletBinding()]
    Param ()
      
  Begin{
    Write-Verbose "Verbose: Checking for registry keys."
    if ((Test-Path 'HKLM:\SOFTWARE\LabTech\Service') -eq $False){
        Write-Output "ERROR: Unable to find information on LTSvc. Make sure the service is running."
        Break    
    }
    $exclude = "PSParentPath","PSChildName","PSDrive","PSProvider","PSPath"
  }#End Begin
  
  Process{
    Try{
    	$serverInfo = Get-ItemProperty HKLM:\SOFTWARE\LabTech\Service -ErrorAction Stop | Select * -exclude $exclude
        $serverAddress = $serverInfo.'Server Address'
        if ($serverAddress -like '*|*') { $serverInfo.'Server Address' = $serverAddress.Split('|')[0] }
        $serverInfo
    }#End Try
    
    Catch{
      Write-Output "ERROR: There was a problem reading the registry keys. $($Error[0])"
      break
    }#End Catch
  }#End Process
  
  End{
    if ($?){
        $key
    }    
  }#End End
}#End Function Get-LTServiceInfo

Function Get-LTServiceSettings{ 
<#
.SYNOPSIS
    This function will pull all of the registy data into an object.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 
    [CmdletBinding()]
    Param ()
      
  Begin{
    Write-Verbose "Verbose: Checking for registry keys."
    if ((Test-Path 'HKLM:\SOFTWARE\LabTech\Service') -eq $False){
        Write-Output "ERROR: Unable to find LTSvc settings. Make sure the service is running."
        Break    
    }
    $exclude = "PSParentPath","PSChildName","PSDrive","PSProvider","PSPath"
  }#End Begin
  
  Process{
    Try{
        Get-ItemProperty HKLM:\SOFTWARE\LabTech\Service\Settings -ErrorAction Stop | Select * -exclude $exclude
    }#End Try
    
    Catch{
      Write-Output "ERROR: There was a problem reading the registry keys. $($Error[0])"
      break
    }#End Catch
  }#End Process
  
  End{
    if ($?){
        $key
    }    
  }#End End
}#End Function Get-LTServiceSettings

Function Restart-LTService{
<#
.SYNOPSIS
    This function will restart the LabTech Services.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 
  
    [CmdletBinding()]
    Param()
  
  Begin{
    if (!(Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
        Write-Output "ERROR: Services NOT Found" $($Error[0])
        break
    }
  }#End Begin
  
  Process{
    Try{
      Stop-LTService
      Start-LTService
    }#End Try
    
    Catch{
      Write-Output "ERROR: There was an error restarting the services. $($Error[0])"
      break
    }#End Catch
  }#End Process
  
  End{
    If($?){Write-Output "Services Restarted successfully."}
    Else {$Error[0]}
  }#End End
}#End Function Restart-LTService

Function Stop-LTService{
<#
.SYNOPSIS
    This function will stop the LabTech Services.

.DESCRIPTION
    This funtion will verify that the LabTech services are present then attempt to stop them.
    It will then check for any remaining LabTech processes and kill them.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#>   
    [CmdletBinding()]
    Param()
  
  Begin{
    if (!(Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
        Write-Output "ERROR: Services NOT Found" $($Error[0])
        break
    }
  }#End Begin
  
  Process{
    Try{
        Stop-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue
        Get-Process | Where-Object -Property ProcessName -In -Value 'LTTray','LTSVC','LTSvcMon' | Stop-Process -Force -ErrorAction Stop
    }#End Try
    
    Catch{
        Write-Output "ERROR: There was an error stoping the LabTech proccesses. $($Error[0])"  
        break
    }#End Catch
  }#End Process
  
  End{
    If($?){
        Write-Output "Services Stopped successfully."
    }
    Else {$Error[0]}
  }#End End
}#End Function Stop-LTService

Function Start-LTService{
<#
.SYNOPSIS
    This function will start the LabTech Services.

.DESCRIPTION
    This funtion will verify that the LabTech services are present.
    It will then check for any proccess that is using port 42000 and kill it.
    Next it will start the services.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#>
    
    [CmdletBinding()]
    Param()   
   
    Begin{
        if (!(Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
            Write-Output "ERROR: Services NOT Found" $($Error[0])
            break
        }
        #Kill all processes that are using port 42000
        [array]$process = @()
        $netstat = netstat -a -o -n | Select-String 42000
        foreach ($line in $netstat){
            $process += ($line -split '  {3,}')[-1]
        }
        $process = $process | Get-Unique
        foreach ($proc in $process){
            if ($proc -ne 0) {
                Write-Output "Process ID:$proc is using port 42000. Killing process."
                Stop-Process -ID $proc -Force -Verbose
            }
        }
    }#End Begin
  
    Process{
        Try{
            Start-Service 'LTService','LTSvcMon'
        }#End Try
    
        Catch{
            Write-Output "ERROR: There was an error starting theLabTech services. $($Error[0])"
            break
        }#End Catch
    }#End Process
  
    End
    {
        If($?){
            Write-Output "Services Started successfully."
        }
        else{
             $($Error[0])
        }
    }#End End
}#End Function Start-LTService

Function Uninstall-LTService{
<#
.SYNOPSIS
    This function will uninstall the LabTech agent from the machine.

.DESCRIPTION
    This function will stop all the LabTech services. It will then download the current agent install MSI and issue an uninstall command.
    It will then download and run Agent_Uninstall.exe from the LabTech server. It will then scrub any remaining file/registry/service.

.PARAMETER Server
    This is the URL to your LabTech server. 
    example: https://lt.domain.com
    This is used to download the uninstallers.
    If no server is provided the uninstaller will use Get-LTServiceInfo to get the server address.

.EXAMPLE
    Uninstall-LTService
    This will uninstall the LabTech agent using the server address in the registry.

.EXAMPLE
    Uninstall-LTService -Server 'https://lt.domain.com'
    This will uninstall the LabTech agent using the provided server URL to download the uninstallers.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 

    [CmdletBinding()]
    Param(
        [Parameter()]
        [string]$Server = (Get-LTServiceInfo).'Server Address'   
    )   
    Begin{
        if (!$Server){
            $Server = Read-Host -Prompt 'Provide the URL to you LabTech server (https://labtech.labtechconsulting.com)'
            if ($server -notlike 'http*://*'){
                Write-Output 'Server address is not formatted correctly.'
                Write-Output 'Example: https://labtech.labtechconsulting.com'
                Break
            }
        }
        Write-Output "Starting uninstall."
        New-PSDrive HKU Registry HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
        $regs = @('HKLM:\Software\LabTech',
          'HKLM:\Software\Wow6432Node\LabTech',
          'Registry::HKEY_CLASSES_ROOT\Installer\Dependencies\{3426921d-9ad5-4237-9145-f15dee7e3004}',
          'Registry::HKEY_CLASSES_ROOT\Installer\Dependencies\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}',
          'Registry::HKEY_CLASSES_ROOT\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
          'Registry::HKEY_CURRENT_USER\SOFTWARE\LabTech\Service',
          'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{3426921d-9ad5-4237-9145-f15dee7e3004}',
          'Registry::HKEY_CURRENT_USER\SOFTWARE\LabTech\LabVNC',
          'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Appmgmt\{40bf8c82-ed0d-4f66-b73e-58a3d7ab6582}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{09DF1DCA-C076-498A-8370-AD6F878B6C6A}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{15DD3BF6-5A11-4407-8399-A19AC10C65D0}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{3C198C98-0E27-40E4-972C-FDC656EC30D7}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{459C65ED-AA9C-4CF1-9A24-7685505F919A}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{7BE3886B-0C12-4D87-AC0B-09A5CE4E6BD6}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{7E092B5C-795B-46BC-886A-DFFBBBC9A117}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{9D101D9C-18CC-4E78-8D78-389E48478FCA}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{B0B8CDD6-8AAA-4426-82E9-9455140124A1}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{B1B00A43-7A54-4A0F-B35D-B4334811FAA4}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{BBC521C8-2792-43FE-9C91-CCA7E8ACBCC9}',
          'Registry::HKEY_CLASSES_ROOT\CLSID\{C59A1D54-8CD7-4795-AEDD-F6F6E2DE1FE7}',
          'Registry::HKEY_CLASSES_ROOT\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
          'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Managed\\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
          'Registry::HKEY_CURRENT_USER\Software\Microsoft\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F',
          'HKU:\*\Software\Microsoft\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F')
        $installer = $server + '/Labtech/Deployment.aspx?Probe=1&installType=msi&MSILocations=1'
        $installerTest = invoke-webrequest $installer -DisableKeepAlive -UseBasicParsing -Method head
        if ($installerTest.StatusCode -ne 200) {
            Write-Output 'Unable to download Agent_Install from server.'
            break
        }
        $uninstaller = $server +'/Labtech/Deployment.aspx?probe=1&ID=-2'
        $uninstallerTest = invoke-webrequest $uninstaller -DisableKeepAlive -UseBasicParsing -Method head
        if ($uninstallerTest.StatusCode -ne 200) {
            Write-Output 'Unable to download Agent_Uninstall from server.'
            break
        }
        $xarg = "/x $installer /qn"
    }#End Begin
  
    Process{
        Try{
            Get-Process | Where-Object -Property ProcessName -In -Value 'LTTray','LTSVC','LTSvcMon' | Stop-Process -Force -ErrorAction SilentlyContinue

            #Unregister DLL
            regsvr32 /u C:\WINDOWS\LTSvc\wodVPN.dll /s

            #Cleanup previous uninstallers
            Remove-Item 'Uninstall.exe','Uninstall.exe.config' -ErrorAction SilentlyContinue

            #Run MSI uninstaller for current installer
            Start-Process -Wait -FilePath msiexec -ArgumentList $xarg

            #Download and run Agent_Uninstall.exe
            Invoke-RestMethod -Uri $uninstaller -OutFile $env:windir\temp\Agent_Uninstall.exe
            Start-Process "$env:windir\temp\Agent_Uninstall.exe"
            Start-Sleep -Seconds 30

            #Remove %ltsvcdir%
            Remove-Item -Recurse -Force "$env:windir\LTSvc" -ErrorAction SilentlyContinue

            #Remove all registry keys
            foreach ($reg in $regs) {
                remove-item -Recurse -Path $reg -ErrorAction SilentlyContinue
            }

            #Remove Services
            Start-Process -FilePath sc -ArgumentList "delete LTService" -Wait
            Start-Process -FilePath sc -ArgumentList "delete LTSvcMon" -Wait

        }#End Try
    
        Catch{
            Write-Output "ERROR: There was an error durring the uninstall process. $($Error[0])"
            break 
        }#End Catch
    }#End Process
  
    End{
        If($?){
            Write-Output "LabTech has been successfully uninstalled."
        }
        else {
            $($Error[0])
        }
    }#End End
}#End Function Uninstall-LTService

Function Install-LTService{
<#
.SYNOPSIS
    This function will install the LabTech agent on the machine.

.DESCRIPTION
    This function will install the LabTech agent on the machine with the specified server/password/location.

.PARAMETER Server
    This is the URL to your LabTech server. 
    example: https://lt.domain.com
    This is used to download the uninstallers.
    (Get-LTServiceInfo).'Server Address'

.PARAMETER Password
    This is the server password that agents use to authenticate with the LabTech server.
    (Get-LTServiceInfo).ServerPassword

.PARAMETER LocationID
    This is the LocationID of the location that the agent will be put into.
    (Get-LTServiceInfo).LocationID

.PARAMETER Hide
    This will call Hide-LTService after the install.

.EXAMPLE
    Install-LTService -Server https://lt.domain.com -Password sQWZzEDYKFFnTT0yP56vgA== -LocationID 42
    This will install the LabTech agent using the provided server URL, Password, and LocationID.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [string]$Server,
        [Parameter(Mandatory=$True)]
        [string]$Password,
        [Parameter(Mandatory=$True)]
        [int]$LocationID,
        [switch]$Hide
	    
    )   
    Begin{
        if (Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue) {
            Write-Output "LabTech already installed."
            Break
        }
        if ($server -notlike 'http*://*'){
            Write-Output 'Server address is not formatted correctly.'
            Write-Output 'Example: http://labtech.labtechconsulting.com'
            Break
        }
        $installer = "$($Server)/Labtech/Deployment.aspx?Probe=1&installType=msi&MSILocations=$LocationID"
        $installerTest = invoke-webrequest $installer -DisableKeepAlive -UseBasicParsing -Method head
        if ($installerTest.StatusCode -ne 200) {
            Write-Output 'Unable to download Agent_Install from server.'
            break
        }
        $iarg = '/i ' + $installer + ' SERVERADDRESS=' + $Server + ' SERVERPASS=' + $Password + ' LOCATION=' + $LocationID + ' /qn /l ' + $env:TEMP + '/LTAgentInstall.log'
        Write-Output "Starting install."
    }#End Begin
  
    Process{
        Try{
            Start-Process -Wait -FilePath msiexec -ArgumentList $iarg
            Write-Host -NoNewline "Waiting for agent to register." 
            Start-Sleep 5
            $timeout = new-timespan -Minutes 1
            $sw = [diagnostics.stopwatch]::StartNew()
            while (((Get-LTServiceInfo).ID -lt 1 -or !(Get-LTServiceInfo).ID) -and $sw.elapsed -lt $timeout){
                Write-Host -NoNewline '.'
                Start-Sleep 2
            }
            if ($Hide){Hide-LTAddRemove}
        }#End Try
    
        Catch{
            Write-Output "ERROR: There was an error durring the install process. $($Error[0])"
            break
        }#End Catch
    }#End Process
  
    End{
        If((Get-LTServiceInfo).ID2 -lt 1 -or !(Get-LTServiceInfo).ID){
            Write-Host ""
            Write-Output "LabTech has been installed successfully. Agent ID: $((Get-LTServiceInfo).ID) LocationID: $((Get-LTServiceInfo).LocationID)"
        }
        else {
            Write-Output "ERROR: There was an error installing LabTech. Check the log, $($env:TEMP)\LTAgentInstall.log" $($Error[0])
        }
    }#End End
}#End Function Install-LTService

Function Reinstall-LTService{
<#
.SYNOPSIS
    This function will reinstall the LabTech agent from the machine.

.DESCRIPTION
    This function will stop all the LabTech services. It will then download the current agent install MSI and issue an uninstall command.
    It will then download and run Agent_Uninstall.exe from the LabTech server. It will then scrub any remaining file/registry/service.

.PARAMETER Server
    This is the URL to your LabTech server. 
    example: https://lt.domain.com
    This is used to download the uninstallers.
    If no server is provided the uninstaller will use Get-LTServiceInfo to get the server address.

.EXAMPLE
    Uninstall-LTService
    This will uninstall the LabTech agent using the server address in the registry.

.EXAMPLE
    Uninstall-LTService -Server 'https://lt.domain.com'
    This will uninstall the LabTech agent using the provided server URL to download the uninstallers.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 
    Param(
        [string]$Server = (Get-LTServiceInfo).'Server Address' ,
        [string]$Password = (Get-LTServiceInfo).ServerPassword ,
        [string]$LocationID = (Get-LTServiceInfo).LocationID   
    )
           
    Begin{
        if (!$Server){
            $Server = Read-Host -Prompt 'Provide the URL to you LabTech server (https://lt.domain.com):'
            if ($server -notlike 'http*://*'){
                Write-Output 'Server address is not formatted correctly.'
                Write-Output 'Example: https://labtech.labtechconsulting.com'
                Break
            }
        }
        if (!$Password){
            $Password = Read-Host -Prompt 'Provide the server password:'
        }
        if (!$LocationID){
            $LocationID = Read-Host -Prompt 'Provide the LocationID'
        }
        Write-host "Reinstalling LabTech with the following information, Server:$Server Password:$Password LocationID:$LocationID"
         
    }#End Begin
  
    Process{
        Try{
            Uninstall-LTService -Server $Server
            Install-LTService -Server $Server -Password $Password -LocationID $LocationID
        }#End Try
    
        Catch{
            Write-Output "ERROR: There was an error durring the reinstall process. $($Error[0])"
            break 
        }#End Catch
    }#End Process
  
    End{
        If($?){
        }
        else {
            $($Error[0])
        }
    }#End End
}#End Function Uninstall-LTService

Function Get-LTError{
<#
.SYNOPSIS
    This will pull the %ltsvcdir%\LTErrors.txt file into an object.

.EXAMPLE
    Get-LTError | where {(Get-date $_.Time) -gt (get-date).AddHours(-24)}
    Get a list of all errors in the last 24hr

.EXAMPLE
    Get-LTServiceInfo | Out-Gridview
    Open the log file in a sortable searchable window.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 

    [CmdletBinding()]
    Param()
    
    Begin{
        if ($(Test-Path -Path $env:windir\LTSvc\LTErrors.txt) -eq $False) {
            Write-Output "ERROR: Unable to find log." $($Error[0])
            break
        }
    }#End Begin
  
    Process{
        Try{
            Import-Csv -Delimiter - -Header Service,Time,Message -Path "$((Get-LTServiceInfo).BasePath)\LTErrors.txt"
        }#End Try
    
        Catch{
            Write-Output "ERROR: There was an error reading the log. $($Error[0])"
            break
        }#End Catch
    }#End Process
  
    End{
        if ($?){
        }
        Else {$Error[0]}
        
    }#End End
}#End Function Get-LTError

Function Reset-LTService{
<#
.SYNOPSIS
    This function will remove local settings on the aggent.

.DESCRIPTION
    This function can remove some of the agents local settings.
    ID, MAC, LocationID
    The function will stop the services, make the change, then start the services.
    Resetting all of these will force the agent to check in as a new agent.
    If you have MAC filtering enabled it should check back in with the same ID.
    This function is usefull for duplicate agents.

.EXAMPLE
    Reset-LTService
    This resets the ID, MAC and LocationID on the agent. 

.EXAMPLE
    Reset-LTService -ID
    This resets only the ID of the agent.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 

    [CmdletBinding()]
    Param(
        [switch]$ID,
        [switch]$Location,
        [switch]$MAC
	    
    )   
    
    Begin{
        if (!(Get-Service 'LTService','LTSvcMon' -ErrorAction SilentlyContinue)) {
            Write-Output "ERROR: LabTech Services NOT Found" $($Error[0])
            break
        }
        $Reg = 'HKLM:\Software\LabTech\Service'
        if (!($ID -and $LocationID -and $MAC)){
            $ID=$true
            $Location=$true
            $MAC=$true
        }
        Write-Output "OLD ID: $((Get-LTServiceInfo).ID) LocationID: $((Get-LTServiceInfo).LocationID) MAC: $((Get-LTServiceInfo).MAC)"
        
    }#End Begin
  
    Process{
        Try{
            Stop-LTService
            if ($ID) {
                Write-Output ".Removing ID"
                Remove-ItemProperty -Name ID -Path $Reg -ErrorAction SilentlyContinue            
            }
            if ($Location) {
                Write-Output ".Removing LocationID"
                Remove-ItemProperty -Name LocationID -Path $Reg -ErrorAction SilentlyContinue
            }
            if ($MAC) {
                Write-Output ".Removing MAC"
                Remove-ItemProperty -Name MAC -Path $Reg -ErrorAction SilentlyContinue
            }
            Start-LTService
            $timeout = new-timespan -Minutes 1
            $sw = [diagnostics.stopwatch]::StartNew()
            While (!(Get-LTServiceInfo).ID -or !(Get-LTServiceInfo).LocationID -or !(Get-LTServiceInfo).MAC -and $sw.elapsed -lt $timeout){
                Write-Host -NoNewline '.'
                Start-Sleep 2
            }

        }#End Try
    
        Catch{
            Write-Output "ERROR: There was an error durring the reset process. $($Error[0])"
            break
        }#End Catch
    }#End Process
  
    End{
        if ($?){
            Write-Output ""
            Write-Output "NEW ID: $((Get-LTServiceInfo).ID) LocationID: $((Get-LTServiceInfo).LocationID) MAC: $((Get-LTServiceInfo).MAC)"
        }
        Else {$Error[0]}
    }#End End
}#End Function Get-LTError

Function Hide-LTAddRemove{
<#
.SYNOPSIS
    This function hides the LabTech install from add/remove programs list.

.DESCRIPTION
    This function will rename the DisplayName registry key to hide it from the add/remove programs list.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param()

    Begin{
        $RegRoot = 'HKLM:\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F'
        if (Get-ItemProperty $RegRoot -Name ProductName -ErrorAction SilentlyContinue) {
            Write-Output "LabTech found in add/remove programs."
        }
        else {
            if (Get-ItemProperty $RegRoot -Name HiddenProductName -ErrorAction SilentlyContinue) {
                Write-Output "LabTech already hidden from add/remove programs."
                break
            }    
        }
    }#End Begin
  
    Process{
        Try{
            Rename-ItemProperty $RegRoot -Name ProductName -NewName HiddenProductName
        }#End Try
    
        Catch{
            Write-Output "There was an error renaming the registry key. $($Error[0])"
            break
        }#End Catch
    }#End Process
  
    End{
        if($?){
            Write-Output "LabTech is now hidden from Add/Remove Programs."
        }
        else {$Error[0]}
    }#End End
}#End Function Hide-LTAddRemove

Function Show-LTAddRemove{
<#
.SYNOPSIS
    This function shows the LabTech install in the add/remove programs list.

.DESCRIPTION
    This function will rename the HiddenDisplayName registry key to show it in the add/remove programs list.
    If there is not HiddenDisplayName key the function will import a new entry.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param()

    Begin{
        if (Get-ItemProperty $RegRoot -Name ProductName -ErrorAction SilentlyContinue){
            Write-Output "LabTech already shown in add/remove programs."
            break
        }
        $RegRoot = 'HKLM:\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F'
    }#End Begin
  
    Process{
        Try{
            if (Get-ItemProperty $RegRoot -Name HiddenProductName -ErrorAction SilentlyContinue){
                Rename-ItemProperty $RegRoot -Name HiddenProductName -NewName ProductName
            }
            else{
                $RegImport = @'
[HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F]
"ProductName"="LabTech® Software Remote Agent"
"PackageCode"="3C90D7DE9DA96DD40BE91B7D022A49F0"
"Language"=dword:00000409
"Version"=dword:0a0500e2
"Assignment"=dword:00000001
"AdvertiseFlags"=dword:00000184
"ProductIcon"="C://Windows\\Installer\\{3F460D4C-D217-46B4-80B6-B5ED50BD7CF5}\\LabTeCh.ico"
"InstanceType"=dword:00000000
"AuthorizedLUAApp"=dword:00000000
"DeploymentFlags"=dword:00000003
"Clients"=hex(7):3a,00,00,00,00,00
[HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F\SourceList]
"PackageName"="Deployment.aspx?Probe=1&installType=msi&MSILocations=1"
[HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F\SourceList\Media]
"1"=";"
[HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\C4D064F3712D4B64086B5BDE05DBC75F\SourceList\URL]
"SourceType"=dword:00000002
'@
                $RegImport | Out-File "$env:TEMP\LT.reg" -Force
                Start-Process -Wait -FilePath reg -ArgumentList "import $($env:TEMP)\LT.reg"
                Remove-Item "$env:TEMP\LT.reg" -Force
                New-ItemProperty -Path "$RegRoot\SourceList" -Name LastUsedSource -Value "u;1;$(((Get-LTServiceInfo).'Server Address').Split(';'))/Labtech/" -PropertyType ExpandString -Force | Out-Null
                New-ItemProperty -Path "$RegRoot\SourceList\URL" -Name 1 -Value "$(((Get-LTServiceInfo).'Server Address').Split(';'))/Labtech/" -PropertyType ExpandString -Force | Out-Null
            }
            
        }#End Try
    
        Catch{
            Write-Output "There was an error renaming the registry key. $($Error[0])"
            break
        }#End Catch
    }#End Process
  
    End{
        if ($?) {
            Write-Output "LabTech is now shown in Add/Remove Programs."
        }
        Else{$Error[0]}
    }#End End
}#End Function Show-LTAddRemove

Function Test-LTPorts{
<#
.SYNOPSIS
    This function will attempt to connect to all required TCP ports.

.DESCRIPTION
    The function will make sure that LTTray is using UDP 42000.
    It will then test all the required TCP ports.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#>
    [CmdletBinding()]
    Param()

    Begin{
        Function TestPort{
        Param(
            [parameter(ParameterSetName='ComputerName', Position=0)]
            [string]
            $ComputerName,

            [parameter(ParameterSetName='IP', Position=0)]
            [System.Net.IPAddress]
            $IPAddress,

            [parameter(Mandatory=$true , Position=1)]
            [int]
            $Port

            )

        $RemoteServer = If ([string]::IsNullOrEmpty($ComputerName)) {$IPAddress} Else {$ComputerName};
    
        $test = New-Object System.Net.Sockets.TcpClient;
        Try
        {
            Write-Output "Connecting to $($RemoteServer):$Port (TCP)..";
            $test.Connect($RemoteServer, $Port);
            Write-Output "Connection successful";
        }
        Catch
        {
            Write-Output "ERROR: Connection failed";
            $Global:PortTestError = 1
        }
        Finally
        {
            $test.Dispose();
        }

    }#End Function TestPort
        $Servers = ((Get-LTServiceInfo).'server address'.Split(';')).trimstart('https://')
        [array]$process = @()
    }#End Begin
  
      Process{
        Try{
            #Get all processes that are using port 42000
            $netstat = netstat -a -o -n | Select-String 42000
            foreach ($line in $netstat) {
                $process += ($line -split '  {3,}')[-1]
            }
            $process = $process | Get-Unique;
            foreach ($proc in $process) {
                if ((Get-Process -id $proc).ProcessName -eq 'LTSvc') {
                    Write-Output "LTSvc is using port 42000"
                }
                else {
                    Write-Output "Error: $((Get-Process -id $proc).ProcessName) is using port 42000"
                }
            }
    
            foreach ($Server in $Servers) {
                Write-Output "Testing connectivity to required TCP ports"
                TestPort -ComputerName $Server -Port 70
                TestPort -ComputerName $Server -Port 80
                TestPort -ComputerName $Server -Port 443
                TestPort -ComputerName mediator.labtechsoftware.com -Port 8002
            }

        }#End Try
    
        Catch{
          Write-Output "ERROR: There was an error testing the ports. $($Error[0])"
          break          
        }#End Catch
      }#End Process
  
      End{
        If($?){
          Write-Output "Finished"
        }
        else{$Error[0]}
      }#End End

}#End Function Test-LTPorts

Function Get-LTLogging{ 
<#
.SYNOPSIS
    This function will pull the logging level of the LabTech service.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 
    [CmdletBinding()]
    Param ()
      
  Begin{
    Write-Verbose "Verbose: Checking for registry keys."
    if ((Test-Path 'HKLM:\SOFTWARE\LabTech\Service\settings') -eq $False){
        Write-Output "ERROR: Unable to find logging settings for LTSvc. Make sure the service is running."
        Break    
    }
  }#End Begin
  
  Process{
    Try{
        $Value = (Get-LTServiceSettings).Debuging
    }#End Try
    
    Catch{
      Write-Output "ERROR: There was a problem reading the registry key. $($Error[0])"
      break
    }#End Catch
  }#End Process
  
  End{
    if ($?){
        if($value -eq 1){
            Write-Host "Current logging level: Normal"
            break
        }
        if($value -eq 1000){
            Write-Host "Current logging level: Verbose"
            break
        }
        else{
            Write-Host "ERROR: Unknown Logging level $((Get-LTServiceInfo).Debuging)"
        }
    }    
  }#End End
}#End Function Get-LTLogging

Function Set-LTLogging{ 
<#
.SYNOPSIS
    This function will pull all of the registy data into an object.

.NOTES
    Version:        1.0
    Author:         Chris Taylor
    website:        labtechconsulting.com
    Creation Date:  3/14/2016
    Purpose/Change: Initial script development
.LINK
    http://labtechconsulting.com
#> 
   Param (
        [switch]$Normal,
        [switch]$Verbose
    )

      
  Begin{
    if ($Normal -ne $true -and $Verbose -ne $true ){
        Write-Output "Please provide a logging level. -Normal or -Verbose"
        break
    }

  }#End Begin
  
  Process{
    Try{
        Stop-LTService
        if ($Normal){
            Set-ItemProperty HKLM:\SOFTWARE\LabTech\Service\Settings -Name 'Debuging' -Value 1
        }
        if($Verbose){
            Set-ItemProperty HKLM:\SOFTWARE\LabTech\Service\Settings -Name 'Debuging' -Value 1000
        }
        Start-LTService
    }#End Try
    
    Catch{
      Write-Output "ERROR: There was a problem writing the registry key. $($Error[0])"
      break
    }#End Catch
  }#End Process
  
  End{
    if ($?){
        Get-LTLogging          
    }    
  }#End End
}#End Function Set-LTSLogging

#endregion Functions
