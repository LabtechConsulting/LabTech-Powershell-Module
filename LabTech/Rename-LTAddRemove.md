# Rename-LTAddRemove
## SYNOPSIS
This function renames the LabTech install as shown in the Add/Remove Programs list.
## SYNTAX
```powershell
Rename-LTAddRemove [-Name] <Object> [[-PublisherName] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```
## DESCRIPTION
This function will change the value of the DisplayName registry key to effect Add/Remove Programs list.
## PARAMETERS
### -Name &lt;Object&gt;
This is the Name for the LabTech Agent as displayed in the list of installed software.
```
Required                    true
Position                    1
Default value
Accept pipeline input       false
Accept wildcard characters  false
```
### -PublisherName &lt;String&gt;
This is the Name for the Publisher of the LabTech Agent as displayed in the list of installed software.
```
Required                    false
Position                    2
Default value
Accept pipeline input       false
Accept wildcard characters  false
```
### -WhatIf &lt;SwitchParameter&gt;

```
Required                    false
Position                    named
Default value
Accept pipeline input       false
Accept wildcard characters  false
```
### -Confirm &lt;SwitchParameter&gt;

```
Required                    false
Position                    named
Default value
Accept pipeline input       false
Accept wildcard characters  false
```
## NOTES
Version:        1.2

Author:         Chris Taylor

Website:        labtechconsulting.com

Creation Date:  5/14/2017

Purpose/Change: Initial script development



Update Date: 6/1/2017

Purpose/Change: Updates for better overall compatibility, including better support for PowerShell V2



Update Date: 3/12/2018

Purpose/Change: Support for ShouldProcess to enable -Confirm and -WhatIf. 
