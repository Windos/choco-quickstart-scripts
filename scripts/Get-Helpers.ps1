# Helper Functions for the various QSG scripts

#region Nexus functions (Start-C4BNexusSetup.ps1)
function Wait-Nexus {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::tls12
    Do {
        $response = try {
            Invoke-WebRequest $("http://localhost:8081") -ErrorAction Stop
        }
        catch {
            $null
        }
        
    } until($response.StatusCode -eq '200')
    Write-Host "Nexus is ready!"

}

function Invoke-NexusScript {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [String]
        $ServerUri,

        [Parameter(Mandatory)]
        [Hashtable]
        $ApiHeader,
    
        [Parameter(Mandatory)]
        [String]
        $Script
    )

    $scriptName = [GUID]::NewGuid().ToString()
    $body = @{
        name    = $scriptName
        type    = 'groovy'
        content = $Script
    }

    # Call the API
    $baseUri = "$ServerUri/service/rest/v1/script"

    #Store the Script
    $uri = $baseUri
    Invoke-RestMethod -Uri $uri -ContentType 'application/json' -Body $($body | ConvertTo-Json) -Header $ApiHeader -Method Post
    #Run the script
    $uri = "{0}/{1}/run" -f $baseUri, $scriptName
    $result = Invoke-RestMethod -Uri $uri -ContentType 'text/plain' -Header $ApiHeader -Method Post
    #Delete the Script
    $uri = "{0}/{1}" -f $baseUri, $scriptName
    Invoke-RestMethod -Uri $uri -Header $ApiHeader -Method Delete -UseBasicParsing

    $result

}

function Connect-NexusServer {
    <#
    .SYNOPSIS
    Creates the authentication header needed for REST calls to your Nexus server
    
    .DESCRIPTION
    Creates the authentication header needed for REST calls to your Nexus server
    
    .PARAMETER Hostname
    The hostname or ip address of your Nexus server
    
    .PARAMETER Credential
    The credentials to authenticate to your Nexus server
    
    .PARAMETER UseSSL
    Use https instead of http for REST calls. Defaults to 8443.
    
    .PARAMETER Sslport
    If not the default 8443 provide the current SSL port your Nexus server uses
    
    .EXAMPLE
    Connect-NexusServer -Hostname nexus.fabrikam.com -Credential (Get-Credential)
    .EXAMPLE
    Connect-NexusServer -Hostname nexus.fabrikam.com -Credential (Get-Credential) -UseSSL
    .EXAMPLE
    Connect-NexusServer -Hostname nexus.fabrikam.com -Credential $Cred -UseSSL -Sslport 443
    #>
    [cmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/Connect-NexusServer/')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Server')]
        [String]
        $Hostname,

        [Parameter(Mandatory, Position = 1)]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter()]
        [Switch]
        $UseSSL,

        [Parameter()]
        [String]
        $Sslport = '8443'
    )

    process {

        if ($UseSSL) {
            $script:protocol = 'https'
            $script:port = $Sslport
        }
        else {
            $script:protocol = 'http'
            $script:port = '8081'
        }

        $script:HostName = $Hostname

        $credPair = "{0}:{1}" -f $Credential.UserName, $Credential.GetNetworkCredential().Password

        $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($credPair))

        $script:header = @{ Authorization = "Basic $encodedCreds" }

        try {
            $url = "$($protocol)://$($Hostname):$($port)/service/rest/v1/status"

            $params = @{
                Headers     = $header
                ContentType = 'application/json'
                Method      = 'GET'
                Uri         = $url
            }

            $result = Invoke-RestMethod @params -ErrorAction Stop
            Write-Host "Connected to $Hostname" -ForegroundColor Green
        }

        catch {
            $_.Exception.Message
        }
    }
}

function Invoke-Nexus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]
        $UriSlug,

        [Parameter()]
        [Hashtable]
        $Body,

        [Parameter()]
        [Array]
        $BodyAsArray,

        [Parameter()]
        [String]
        $BodyAsString,

        [Parameter()]
        [String]
        $File,

        [Parameter()]
        [String]
        $ContentType = 'application/json',

        [Parameter(Mandatory)]
        [String]
        $Method


    )
    process {

        $UriBase = "$($protocol)://$($Hostname):$($port)"
        $Uri = $UriBase + $UriSlug
        $Params = @{
            Headers     = $header
            ContentType = $ContentType
            Uri         = $Uri
            Method      = $Method
        }

        if ($Body) {
            $Params.Add('Body', $($Body | ConvertTo-Json -Depth 3))
        } 
        
        if ($BodyAsArray) {
            $Params.Add('Body', $($BodyAsArray | ConvertTo-Json -Depth 3))
        }

        if ($BodyAsString) {
            $Params.Add('Body', $BodyAsString)
        }

        if ($File) {
            $Params.Remove('ContentType')
            $Params.Add('InFile', $File)
        }

        Invoke-RestMethod @Params
        

    }
}

function Get-NexusUserToken {
    <#
    .SYNOPSIS
    Fetches a User Token for the provided credential
    
    .DESCRIPTION
    Fetches a User Token for the provided credential
    
    .PARAMETER Credential
    The Nexus user for which to receive a token
    
    .NOTES
    This is a private function not exposed to the end user. 
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [PSCredential]
        $Credential
    )

    process {
        $UriBase = "$($protocol)://$($Hostname):$($port)"
        
        $slug = '/service/extdirect'

        $uri = $UriBase + $slug

        $data = @{
            action = 'rapture_Security'
            method = 'authenticationToken'
            data   = @("$([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($($Credential.Username))))", "$([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($($Credential.GetNetworkCredential().Password))))")
            type   = 'rpc'
            tid    = 16 
        }

        Write-Verbose ($data | ConvertTo-Json)
        $result = Invoke-RestMethod -Uri $uri -Method POST -Body ($data | ConvertTo-Json) -ContentType 'application/json' -Headers $header
        $token = $result.result.data
        $token
    }

}

function Get-NexusRepository {
    <#
    .SYNOPSIS
    Returns info about configured Nexus repository
    
    .DESCRIPTION
    Returns details for currently configured repositories on your Nexus server
    
    .PARAMETER Format
    Query for only a specific repository format. E.g. nuget, maven2, or docker
    
    .PARAMETER Name
    Query for a specific repository by name
    
    .EXAMPLE
    Get-NexusRepository
    .EXAMPLE
    Get-NexusRepository -Format nuget
    .EXAMPLE
    Get-NexusRepository -Name CompanyNugetPkgs
    #>
    [cmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/Get-NexusRepository/', DefaultParameterSetName = "default")]
    param(
        [Parameter(ParameterSetName = "Format", Mandatory)]
        [String]
        [ValidateSet('apt', 'bower', 'cocoapods', 'conan', 'conda', 'docker', 'gitlfs', 'go', 'helm', 'maven2', 'npm', 'nuget', 'p2', 'pypi', 'r', 'raw', 'rubygems', 'yum')]
        $Format,

        [Parameter(ParameterSetName = "Type", Mandatory)]
        [String]
        [ValidateSet('hosted', 'group', 'proxy')]
        $Type,

        [Parameter(ParameterSetName = "Name", Mandatory)]
        [String]
        $Name
    )


    begin {

        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }

        $urislug = "/service/rest/v1/repositories"
    }
    process {

        switch ($PSCmdlet.ParameterSetName) {
            { $Format } {
                $filter = { $_.format -eq $Format }

                $result = Invoke-Nexus -UriSlug $urislug -Method Get
                $result | Where-Object $filter
                
            }

            { $Name } {
                $filter = { $_.name -eq $Name }

                $result = Invoke-Nexus -UriSlug $urislug -Method Get
                $result | Where-Object $filter

            }

            { $Type } {
                $filter = { $_.type -eq $Type }
                $result = Invoke-Nexus -UriSlug $urislug -Method Get
                $result | Where-Object $filter
            }

            default {
                Invoke-Nexus -UriSlug $urislug -Method Get | ForEach-Object { 
                    [pscustomobject]@{
                        Name       = $_.SyncRoot.name
                        Format     = $_.SyncRoot.format
                        Type       = $_.SyncRoot.type
                        Url        = $_.SyncRoot.url
                        Attributes = $_.SyncRoot.attributes
                    }
                }
            }
        }
    }
}

function Remove-NexusRepository {
    <#
    .SYNOPSIS
    Removes a given repository from the Nexus instance
    
    .DESCRIPTION
    Removes a given repository from the Nexus instance
    
    .PARAMETER Repository
    The repository to remove
    
    .PARAMETER Force
    Disable prompt for confirmation before removal
    
    .EXAMPLE
    Remove-NexusRepository -Repository ProdNuGet
    .EXAMPLE
    Remove-NexusRepository -Repository MavenReleases -Force()
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/Remove-NexusRepository/', SupportsShouldProcess, ConfirmImpact = 'High')]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter( {
                param($command, $WordToComplete, $CommandAst, $FakeBoundParams)
                $repositories = (Get-NexusRepository).Name

                if ($WordToComplete) {
                    $repositories.Where{ $_ -match "^$WordToComplete" }
                }
                else {
                    $repositories
                }
            })]
        [String[]]
        $Repository,

        [Parameter()]
        [Switch]
        $Force
    )
    begin {

        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }

        $urislug = "/service/rest/v1/repositories"
    }
    process {

        $Repository | Foreach-Object {
            $Uri = $urislug + "/$_"

            try {

                if ($Force -and -not $Confirm) {
                    $ConfirmPreference = 'None'
                    if ($PSCmdlet.ShouldProcess("$_", "Remove Repository")) {
                        $result = Invoke-Nexus -UriSlug $Uri -Method 'DELETE' -ErrorAction Stop
                        [pscustomobject]@{
                            Status     = 'Success'
                            Repository = $_
                        }
                    }
                }
                else {
                    if ($PSCmdlet.ShouldProcess("$_", "Remove Repository")) {
                        $result = Invoke-Nexus -UriSlug $Uri -Method 'DELETE' -ErrorAction Stop
                        [pscustomobject]@{
                            Status     = 'Success'
                            Repository = $_
                            Timestamp  = $result.date
                        }
                    }
                }
            }

            catch {
                $_.exception.message
            }
        }
    }
}

function New-NexusNugetHostedRepository {
    <#
    .SYNOPSIS
    Creates a new NuGet Hosted repository
    
    .DESCRIPTION
    Creates a new NuGet Hosted repository
    
    .PARAMETER Name
    The name of the repository
    
    .PARAMETER CleanupPolicy
    The Cleanup Policies to apply to the repository
    
    
    .PARAMETER Online
    Marks the repository to accept incoming requests
    
    .PARAMETER BlobStoreName
    Blob store to use to store NuGet packages
    
    .PARAMETER StrictContentValidation
    Validate that all content uploaded to this repository is of a MIME type appropriate for the repository format
    
    .PARAMETER DeploymentPolicy
    Controls if deployments of and updates to artifacts are allowed
    
    .PARAMETER HasProprietaryComponents
    Components in this repository count as proprietary for namespace conflict attacks (requires Sonatype Nexus Firewall)
    
    .EXAMPLE
    New-NexusNugetHostedRepository -Name NugetHostedTest -DeploymentPolicy Allow
    .EXAMPLE
    $RepoParams = @{
        Name = MyNuGetRepo
        CleanupPolicy = '90 Days'
        DeploymentPolicy = 'Allow'
        UseStrictContentValidation = $true
    }
    
    New-NexusNugetHostedRepository @RepoParams
    .NOTES
    General notes
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/New-NexusNugetHostedRepository/')]
    Param(
        [Parameter(Mandatory)]
        [String]
        $Name,

        [Parameter()]
        [String]
        $CleanupPolicy,

        [Parameter()]
        [Switch]
        $Online = $true,

        [Parameter()]
        [String]
        $BlobStoreName = 'default',

        [Parameter()]
        [ValidateSet('True', 'False')]
        [String]
        $UseStrictContentValidation = 'True',

        [Parameter()]
        [ValidateSet('Allow', 'Deny', 'Allow_Once')]
        [String]
        $DeploymentPolicy,

        [Parameter()]
        [Switch]
        $HasProprietaryComponents
    )

    begin {

        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }

        $urislug = "/service/rest/v1/repositories"

    }

    process {
        $formatUrl = $urislug + '/nuget'

        $FullUrlSlug = $formatUrl + '/hosted'


        $body = @{
            name    = $Name
            online  = [bool]$Online
            storage = @{
                blobStoreName               = $BlobStoreName
                strictContentTypeValidation = $UseStrictContentValidation
                writePolicy                 = $DeploymentPolicy
            }
            cleanup = @{
                policyNames = @($CleanupPolicy)
            }
        }

        if ($HasProprietaryComponents) {
            $Prop = @{
                proprietaryComponents = 'True'
            }
    
            $Body.Add('component', $Prop)
        }

        Write-Verbose $($Body | ConvertTo-Json)
        Invoke-Nexus -UriSlug $FullUrlSlug -Body $Body -Method POST

    }
}

function New-NexusRawHostedRepository {
    <#
    .SYNOPSIS
    Creates a new Raw Hosted repository
    
    .DESCRIPTION
    Creates a new Raw Hosted repository
    
    .PARAMETER Name
    The Name of the repository to create
    
    .PARAMETER Online
    Mark the repository as Online. Defaults to True
    
    .PARAMETER BlobStore
    The blob store to attach the repository too. Defaults to 'default'
    
    .PARAMETER UseStrictContentTypeValidation
    Validate that all content uploaded to this repository is of a MIME type appropriate for the repository format
    
    .PARAMETER DeploymentPolicy
    Controls if deployments of and updates to artifacts are allowed
    
    .PARAMETER CleanupPolicy
    Components that match any of the Applied policies will be deleted
    
    .PARAMETER HasProprietaryComponents
    Components in this repository count as proprietary for namespace conflict attacks (requires Sonatype Nexus Firewall)
    
    .PARAMETER ContentDisposition
    Add Content-Disposition header as 'Attachment' to disable some content from being inline in a browser.
    
    .EXAMPLE
    New-NexusRawHostedRepository -Name BinaryArtifacts -ContentDisposition Attachment
    .EXAMPLE
    $RepoParams = @{
        Name = 'BinaryArtifacts'
        Online = $true
        UseStrictContentTypeValidation = $true
        DeploymentPolicy = 'Allow'
        CleanupPolicy = '90Days',
        BlobStore = 'AmazonS3Bucket'
    }
    New-NexusRawHostedRepository @RepoParams
    
    .NOTES
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/New-NexusRawHostedRepository/', DefaultParameterSetname = "Default")]
    Param(
        [Parameter(Mandatory)]
        [String]
        $Name,

        [Parameter()]
        [Switch]
        $Online = $true,

        [Parameter()]
        [String]
        $BlobStore = 'default',

        [Parameter()]
        [Switch]
        $UseStrictContentTypeValidation,

        [Parameter()]
        [ValidateSet('Allow', 'Deny', 'Allow_Once')]
        [String]
        $DeploymentPolicy = 'Allow_Once',

        [Parameter()]
        [String]
        $CleanupPolicy,

        [Parameter()]
        [Switch]
        $HasProprietaryComponents,

        [Parameter(Mandatory)]
        [ValidateSet('Inline', 'Attachment')]
        [String]
        $ContentDisposition
    )

    begin {

        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }

        $urislug = "/service/rest/v1/repositories/raw/hosted"

    }

    process {

        $Body = @{
            name      = $Name
            online    = [bool]$Online
            storage   = @{
                blobStoreName               = $BlobStore
                strictContentTypeValidation = [bool]$UseStrictContentTypeValidation
                writePolicy                 = $DeploymentPolicy.ToLower()
            }
            cleanup   = @{
                policyNames = @($CleanupPolicy)
            }
            component = @{
                proprietaryComponents = [bool]$HasProprietaryComponents
            }
            raw       = @{
                contentDisposition = $ContentDisposition.ToUpper()
            }
        }

        Write-Verbose $($Body | ConvertTo-Json)
        Invoke-Nexus -UriSlug $urislug -Body $Body -Method POST


    }
}

function Get-NexusRealm {
    <#
    .SYNOPSIS
    Gets Nexus Realm information
    
    .DESCRIPTION
    Gets Nexus Realm information
    
    .PARAMETER Active
    Returns only active realms
    
    .EXAMPLE
    Get-NexusRealm
    .EXAMPLE
    Get-NexusRealm -Active
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/Get-NexusRealm/')]
    Param(
        [Parameter()]
        [Switch]
        $Active
    )

    begin {

        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }

        
        $urislug = "/service/rest/v1/security/realms/available"
        

    }

    process {

        if ($Active) {
            $current = Invoke-Nexus -UriSlug $urislug -Method 'GET'
            $urislug = '/service/rest/v1/security/realms/active'
            $Activated = Invoke-Nexus -UriSlug $urislug -Method 'GET'
            $current | Where-Object { $_.Id -in $Activated }
        }
        else {
            $result = Invoke-Nexus -UriSlug $urislug -Method 'GET' 

            $result | Foreach-Object {
                [pscustomobject]@{
                    Id   = $_.id
                    Name = $_.name
                }
            }
        }
    }
}

function Enable-NexusRealm {
    <#
    .SYNOPSIS
    Enable realms in Nexus
    
    .DESCRIPTION
    Enable realms in Nexus
    
    .PARAMETER Realm
    The realms you wish to activate
    
    .EXAMPLE
    Enable-NexusRealm -Realm 'NuGet Api-Key Realm', 'Rut Auth Realm'
    .EXAMPLE
    Enable-NexusRealm -Realm 'LDAP Realm'
    
    .NOTES
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/Enable-NexusRealm/')]
    Param(
        [Parameter(Mandatory)]
        [ArgumentCompleter( {
                param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                $r = (Get-NexusRealm).name

                if ($WordToComplete) {
                    $r.Where($_ -match "^$WordToComplete")
                }
                else {
                    $r
                }
            }
        )]
        [String[]]
        $Realm
    )

    begin {

        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }

        $urislug = "/service/rest/v1/security/realms/active"

    }

    process {

        $collection = @()

        Get-NexusRealm -Active | ForEach-Object { $collection += $_.id }

        $Realm | Foreach-Object {

            switch ($_) {
                'Conan Bearer Token Realm' { $id = 'org.sonatype.repository.conan.internal.security.token.ConanTokenRealm' }
                'Default Role Realm' { $id = 'DefaultRole' }
                'Docker Bearer Token Realm' { $id = 'DockerToken' }
                'LDAP Realm' { $id = 'LdapRealm' }
                'Local Authentication Realm' { $id = 'NexusAuthenticatingRealm' }
                'Local Authorizing Realm' { $id = 'NexusAuthorizingRealm' }
                'npm Bearer Token Realm' { $id = 'NpmToken' }
                'NuGet API-Key Realm' { $id = 'NuGetApiKey' }
                'Rut Auth Realm' { $id = 'rutauth-realm' }
            }

            $collection += $id
    
        }

        $body = $collection

        Write-Verbose $($Body | ConvertTo-Json)
        Invoke-Nexus -UriSlug $urislug -BodyAsArray $Body -Method PUT

    }
}

function Get-NexusNuGetApiKey {
    <#
    .SYNOPSIS
    Retrieves the NuGet API key of the given user credential
    
    .DESCRIPTION
    Retrieves the NuGet API key of the given user credential
    
    .PARAMETER Credential
    The Nexus User whose API key you wish to retrieve
    
    .EXAMPLE
    Get-NexusNugetApiKey -Credential (Get-Credential)
    
    .NOTES
    
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/TreasureChest/Security/API%20Key/Get-NexusNuGetApiKey/')]
    Param(
        [Parameter(Mandatory)]
        [PSCredential]
        $Credential
    )

    process {
        $token = Get-NexusUserToken -Credential $Credential
        $base64Token = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($token))
        $UriBase = "$($protocol)://$($Hostname):$($port)"
        
        $slug = "/service/rest/internal/nuget-api-key?authToken=$base64Token&_dc=$(([DateTime]::ParseExact("01/02/0001 21:08:29", "MM/dd/yyyy HH:mm:ss",$null)).Ticks)"

        $uri = $UriBase + $slug

        Invoke-RestMethod -Uri $uri -Method GET -ContentType 'application/json' -Headers $header

    }
}

function New-NexusRawComponent {
    <#
    .SYNOPSIS
    Uploads a file to a Raw repository
    
    .DESCRIPTION
    Uploads a file to a Raw repository
    
    .PARAMETER RepositoryName
    The Raw repository to upload too
    
    .PARAMETER File
    The file to upload
    
    .PARAMETER Directory
    The directory to store the file on the repo
    
    .PARAMETER Name
    The name of the file stored into the repo. Can be different than the file name being uploaded.
    
    .EXAMPLE
    New-NexusRawComponent -RepositoryName GeneralFiles -File C:\temp\service.1234.log
    .EXAMPLE
    New-NexusRawComponent -RepositoryName GeneralFiles -File C:\temp\service.log -Directory logs
    .EXAMPLE
    New-NexusRawComponent -RepositoryName GeneralFile -File C:\temp\service.log -Directory logs -Name service.99999.log
    
    .NOTES
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory)]
        [String]
        $File,

        [Parameter()]
        [String]
        $Directory,

        [Parameter()]
        [String]
        $Name = (Split-Path -Leaf $File)
    )

    process {

        if (-not $Directory) {
            $urislug = "/repository/$($RepositoryName)/$($Name)"
        }
        else {
            $urislug = "/repository/$($RepositoryName)/$($Directory)/$($Name)"

        }
        $UriBase = "$($protocol)://$($Hostname):$($port)"
        $Uri = $UriBase + $UriSlug


        $params = @{
            Uri             = $Uri
            Method          = 'PUT'
            ContentType     = 'text/plain'
            InFile          = $File
            Headers         = $header
            UseBasicParsing = $true
        }

        $null = Invoke-WebRequest @params        
    }
}

function Get-NexusUser {
    <#
    .SYNOPSIS
    Retrieve a list of users. Note if the source is not 'default' the response is limited to 100 users.
    
    .DESCRIPTION
    Retrieve a list of users. Note if the source is not 'default' the response is limited to 100 users.
    
    .PARAMETER User
    The username to fetch
    
    .PARAMETER Source
    The source to fetch from
    
    .EXAMPLE
    Get-NexusUser
    
    .EXAMPLE
    Get-NexusUser -User bob

    .EXAMPLE
    Get-NexusUser -Source default

    .NOTES
    
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/NexuShell/Security/User/Get-NexusUser/')]
    Param(
        [Parameter()]
        [String]
        $User,

        [Parameter()]
        [String]
        $Source
    )

    begin {
        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }
    }

    process {
        $urislug = '/service/rest/v1/security/users'

        if ($User) {
            $urislug = "/service/rest/v1/security/users?userId=$User"
        }

        if ($Source) {
            $urislug = "/service/rest/v1/security/users?source=$Source"
        }

        if ($User -and $Source) {
            $urislug = "/service/rest/v1/security/users?userId=$User&source=$Source"
        }

        $result = Invoke-Nexus -Urislug $urislug -Method GET

        $result | Foreach-Object {
            [pscustomobject]@{
                Username      = $_.userId
                FirstName     = $_.firstName
                LastName      = $_.lastName
                EmailAddress  = $_.emailAddress
                Source        = $_.source
                Status        = $_.status
                ReadOnly      = $_.readOnly
                Roles         = $_.roles
                ExternalRoles = $_.externalRoles
            }
        }
    }
}

function Get-NexusRole {
    <#
    .SYNOPSIS
    Retrieve Nexus Role information
    
    .DESCRIPTION
    Retrieve Nexus Role information
    
    .PARAMETER Role
    The role to retrieve
    
    .PARAMETER Source
    The source to retrieve from
    
    .EXAMPLE
    Get-NexusRole

    .EXAMPLE
    Get-NexusRole -Role ExampleRole
    
    .NOTES
    
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/NexuShell/Security/Roles/Get-NexusRole/')]
    Param(
        [Parameter()]
        [Alias('id')]
        [String]
        $Role,

        [Parameter()]
        [String]
        $Source
    )
    begin { if (-not $header) { throw 'Not connected to Nexus server! Run Connect-NexusServer first.' } }
    process {
        
        $urislug = '/service/rest/v1/security/roles'

        if ($Role) {
            $urislug = "/service/rest/v1/security/roles/$Role"
        }

        if ($Source) {
            $urislug = "/service/rest/v1/security/roles?source=$Source"
        }

        if ($Role -and $Source) {
            $urislug = "/service/rest/v1/security/roles/$($Role)?source=$Source"
        }

        Write-verbose $urislug
        $result = Invoke-Nexus -Urislug $urislug -Method GET

        $result | ForEach-Object {
            [PSCustomObject]@{
                Id          = $_.id
                Source      = $_.source
                Name        = $_.name
                Description = $_.description
                Privileges  = $_.privileges
                Roles       = $_.roles
            }
        }
    }
}

function New-NexusUser {
    <#
    .SYNOPSIS
    Create a new user in the default source.
    
    .DESCRIPTION
    Create a new user in the default source.
    
    .PARAMETER Username
    The userid which is required for login. This value cannot be changed.
    
    .PARAMETER Password
    The password for the new user.
    
    .PARAMETER FirstName
    The first name of the user.
    
    .PARAMETER LastName
    The last name of the user.
    
    .PARAMETER EmailAddress
    The email address associated with the user.
    
    .PARAMETER Status
    The user's status, e.g. active or disabled.
    
    .PARAMETER Roles
    The roles which the user has been assigned within Nexus.
    
    .EXAMPLE
    $params = @{
        Username = 'jimmy'
        Password = ("sausage" | ConvertTo-SecureString -AsPlainText -Force)
        FirstName = 'Jimmy'
        LastName = 'Dean'
        EmailAddress = 'sausageking@jimmydean.com'
        Status = Active
        Roles = 'nx-admin'
    }

    New-NexusUser @params
    
    .NOTES
    
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/NexuShell/Security/User/New-NexusUser/')]
    Param(
        [Parameter(Mandatory)]
        [String]
        $Username,

        [Parameter(Mandatory)]
        [SecureString]
        $Password,

        [Parameter(Mandatory)]
        [String]
        $FirstName,

        [Parameter(Mandatory)]
        [String]
        $LastName,

        [Parameter(Mandatory)]
        [String]
        $EmailAddress,

        [Parameter(Mandatory)]
        [ValidateSet('Active', 'Locked', 'Disabled', 'ChangePassword')]
        [String]
        $Status,

        [Parameter(Mandatory)]
        [ArgumentCompleter({
                param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
            (Get-NexusRole).Id.Where{ $_ -like "*$WordToComplete*" }
            })]
        [String[]]
        $Roles
    )

    process {
        $urislug = '/service/rest/v1/security/users'

        $Body = @{
            userId       = $Username
            firstName    = $FirstName
            lastName     = $LastName
            emailAddress = $EmailAddress
            password     = [System.Net.NetworkCredential]::new($Username, $Password).Password
            status       = $Status
            roles        = $Roles
        }

        Write-Verbose ($Body | ConvertTo-Json)
        $result = Invoke-Nexus -Urislug $urislug -Body $Body -Method POST

        [pscustomObject]@{
            Username      = $result.userId
            FirstName     = $result.firstName
            LastName      = $result.lastName
            EmailAddress  = $result.emailAddress
            Source        = $result.source
            Status        = $result.status
            Roles         = $result.roles
            ExternalRoles = $result.externalRoles
        }
    }
}

function New-NexusRole {
    <#
    .SYNOPSIS
    Creates a new Nexus Role
    
    .DESCRIPTION
    Creates a new Nexus Role
    
    .PARAMETER Id
    The ID of the role
    
    .PARAMETER Name
    The friendly name of the role
    
    .PARAMETER Description
    A description of the role
    
    .PARAMETER Privileges
    Included privileges for the role
    
    .PARAMETER Roles
    Included nested roles
    
    .EXAMPLE
    New-NexusRole -Id SamepleRole

    .EXAMPLE
    New-NexusRole -Id SampleRole -Description "A sample role" -Privileges nx-all
    
    .NOTES
    
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/NexuShell/Security/Roles/New-NexusRole/')]
    Param(
        [Parameter(Mandatory)]
        [String]
        $Id,

        [Parameter(Mandatory)]
        [String]
        $Name,

        [Parameter()]
        [String]
        $Description,

        [Parameter(Mandatory)]
        [String[]]
        $Privileges,

        [Parameter()]
        [String[]]
        $Roles
    )

    begin {
        if (-not $header) { 
            throw 'Not connected to Nexus server! Run Connect-NexusServer first.' 
        } 
    }
    
    process {

        $urislug = '/service/rest/v1/security/roles'
        $Body = @{
            
            id          = $Id
            name        = $Name
            description = $Description
            privileges  = @($Privileges)
            roles       = $Roles
            
        }

        Invoke-Nexus -Urislug $urislug -Body $Body -Method POST | Foreach-Object {
            [PSCustomobject]@{
                Id          = $_.id
                Name        = $_.name
                Description = $_.description
                Privileges  = $_.privileges
                Roles       = $_.roles
            }
        }

    }
}

function Set-NexusAnonymousAuth {
    <#
    .SYNOPSIS
    Turns Anonymous Authentication on or off in Nexus
    
    .DESCRIPTION
    Turns Anonymous Authentication on or off in Nexus
    
    .PARAMETER Enabled
    Turns on Anonymous Auth
    
    .PARAMETER Disabled
    Turns off Anonymous Auth
    
    .EXAMPLE
    Set-NexusAnonymousAuth -Enabled
    #>
    [CmdletBinding(HelpUri = 'https://steviecoaster.dev/NexuShell/Set-NexusAnonymousAuth/')]
    Param(
        [Parameter()]
        [Switch]
        $Enabled,

        [Parameter()]
        [Switch]
        $Disabled
    )

    begin {

        if (-not $header) {
            throw "Not connected to Nexus server! Run Connect-NexusServer first."
        }

        $urislug = "/service/rest/v1/security/anonymous"
    }

    process {

        Switch ($true) {

            $Enabled {
                $Body = @{
                    enabled   = $true
                    userId    = 'anonymous'
                    realmName = 'NexusAuthorizingRealm'
                }

                Invoke-Nexus -UriSlug $urislug -Body $Body -Method 'PUT'
            }

            $Disabled {
                $Body = @{
                    enabled   = $false
                    userId    = 'anonymous'
                    realmName = 'NexusAuthorizingRealm'
                }

                Invoke-Nexus -UriSlug $urislug -Body $Body -Method 'PUT'

            }
        }
    }
}

#endregion

#region SSL functions (Set-SslSecurity.ps1)

function Get-Certificate {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]
        $Thumbprint,

        [Parameter()]
        [string]
        $Subject
    )

    $filter = if ($Thumbprint) {
        { $_.Thumbprint -eq $Thumbprint }
    }
    else {
        { $_.Subject -like "CN=$Subject" }
    }

    $cert = Get-ChildItem -Path Cert:\LocalMachine\My, Cert:\LocalMachine\TrustedPeople |
    Where-Object $filter -ErrorAction Stop |
    Select-Object -First 1

    if ($null -eq $cert) {
        throw "Certificate either not found, or other issue arose."
    }
    else {
        Write-Host "Certification validation passed" -ForegroundColor Green
        $cert
    }
}

function Copy-CertToStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $Certificate
    )

    $location = [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    $trustedCertStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('TrustedPeople', $location)

    try {
        $trustedCertStore.Open('ReadWrite')
        $trustedCertStore.Add($Certificate)
    }
    finally {
        $trustedCertStore.Close()
        $trustedCertStore.Dispose()
    }
}

function Get-RemoteCertificate {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ComputerName,

        [Parameter(Position = 1)]
        [UInt16]$Port = 8443
    )

    $tcpClient = New-Object System.Net.Sockets.TcpClient($ComputerName, $Port)
    $sslProtocolType = [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    try {
        $tlsClient = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), 'false', $callback)
        $tlsClient.AuthenticateAsClient($ComputerName, $null, $sslProtocolType, $false)

        return $tlsClient.RemoteCertificate -as [System.Security.Cryptography.X509Certificates.X509Certificate2]
    }
    finally {
        if ($tlsClient -is [IDisposable]) {
            $tlsClient.Dispose()
        }

        $tcpClient.Dispose()
    }
}

function New-NexusCert {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Thumbprint
    )

    if ((Test-Path C:\ProgramData\nexus\etc\ssl\keystore.jks)) {
        Remove-Item C:\ProgramData\nexus\etc\ssl\keystore.jks -Force
    }

    $KeyTool = "C:\ProgramData\nexus\jre\bin\keytool.exe"
    $password = "chocolatey" | ConvertTo-SecureString -AsPlainText -Force
    $certificate = Get-ChildItem  Cert:\LocalMachine\TrustedPeople\ | Where-Object { $_.Thumbprint -eq $Thumbprint } | Sort-Object | Select-Object -First 1

    Write-Host "Exporting .pfx file to C:\, will remove when finished" -ForegroundColor Green
    $certificate | Export-PfxCertificate -FilePath C:\cert.pfx -Password $password
    Get-ChildItem -Path c:\cert.pfx | Import-PfxCertificate -CertStoreLocation Cert:\LocalMachine\My -Exportable -Password $password
    Write-Warning -Message "You'll now see prompts and other outputs, things are working as expected, don't do anything"
    $string = ("chocolatey" | & $KeyTool -list -v -keystore C:\cert.pfx) -match '^Alias.*'
    $currentAlias = ($string -split ':')[1].Trim()

    $passkey = '9hPRGDmfYE3bGyBZCer6AUsh4RTZXbkw'
    & $KeyTool -importkeystore -srckeystore C:\cert.pfx -srcstoretype PKCS12 -srcstorepass chocolatey -destkeystore C:\ProgramData\nexus\etc\ssl\keystore.jks -deststoretype JKS -alias $currentAlias -destalias jetty -deststorepass $passkey
    & $KeyTool -keypasswd -keystore C:\ProgramData\nexus\etc\ssl\keystore.jks -alias jetty -storepass $passkey -keypass chocolatey -new $passkey

    $xmlPath = 'C:\ProgramData\nexus\etc\jetty\jetty-https.xml'
    [xml]$xml = Get-Content -Path 'C:\ProgramData\nexus\etc\jetty\jetty-https.xml'
    foreach ($entry in $xml.Configure.New.Where{ $_.id -match 'ssl' }.Set.Where{ $_.name -match 'password' }) {
        $entry.InnerText = $passkey
    }

    $xml.OuterXml | Set-Content -Path $xmlPath

    Remove-Item C:\cert.pfx

    $nexusPath = 'C:\ProgramData\sonatype-work\nexus3'
    $configPath = "$nexusPath\etc\nexus.properties"

    $configStrings = @('jetty.https.stsMaxAge=-1', 'application-port-ssl=8443', 'nexus-args=${jetty.etc}/jetty.xml,${jetty.etc}/jetty-https.xml,${jetty.etc}/jetty-requestlog.xml')
    $configStrings | ForEach-Object {
        if ((Get-Content -Raw $configPath) -notmatch [regex]::Escape($_)) {
            $_ | Add-Content -Path $configPath
        }
    }
    
}

function Test-SelfSignedCertificate {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Certificate = (Get-ChildItem -Path Cert:LocalMachine\My | Where-Object { $_.FriendlyName -eq $SubjectWithoutCn })
    )

    process {

        if ($Certificate.Subject -eq $Certificate.Issuer) {
            return $true
        }
        else {
            return $false
        }

    }

}

#endregion

#region CCM functions (Start-C4bCcmSetup.ps1)
function Add-DatabaseUserAndRoles {
    param(
        [parameter(Mandatory = $true)][string] $Username,
        [parameter(Mandatory = $true)][string] $DatabaseName,
        [parameter(Mandatory = $false)][string] $DatabaseServer = 'localhost\SQLEXPRESS',
        [parameter(Mandatory = $false)] $DatabaseRoles = @('db_datareader'),
        [parameter(Mandatory = $false)][string] $DatabaseServerPermissionsOptions = 'Trusted_Connection=true;',
        [parameter(Mandatory = $false)][switch] $CreateSqlUser,
        [parameter(Mandatory = $false)][string] $SqlUserPw
    )

    $LoginOptions = "FROM WINDOWS WITH DEFAULT_DATABASE=[$DatabaseName]"
    if ($CreateSqlUser) {
        $LoginOptions = "WITH PASSWORD='$SqlUserPw', DEFAULT_DATABASE=[$DatabaseName], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF"
    }

    $addUserSQLCommand = @"
USE [master]
IF EXISTS(SELECT * FROM msdb.sys.syslogins WHERE UPPER([name]) = UPPER('$Username'))
BEGIN
DROP LOGIN [$Username]
END

CREATE LOGIN [$Username] $LoginOptions

USE [$DatabaseName]
IF EXISTS(SELECT * FROM sys.sysusers WHERE UPPER([name]) = UPPER('$Username'))
BEGIN
DROP USER [$Username]
END

CREATE USER [$Username] FOR LOGIN [$Username]

"@

    foreach ($DatabaseRole in $DatabaseRoles) {
        $addUserSQLCommand += @"
ALTER ROLE [$DatabaseRole] ADD MEMBER [$Username]
"@
    }

    Write-Output "Adding $UserName to $DatabaseName with the following permissions: $($DatabaseRoles -Join ', ')"
    Write-Debug "running the following: \n $addUserSQLCommand"
    $Connection = New-Object System.Data.SQLClient.SQLConnection
    $Connection.ConnectionString = "server='$DatabaseServer';database='master';$DatabaseServerPermissionsOptions"
    $Connection.Open()
    $Command = New-Object System.Data.SQLClient.SQLCommand
    $Command.CommandText = $addUserSQLCommand
    $Command.Connection = $Connection
    $Command.ExecuteNonQuery()
    $Connection.Close()
}

function New-CcmSalt {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]
        $MinLength = 32,
        [Parameter()]
        [int]
        $SpecialCharCount = 12
    )
    process {
        [System.Web.Security.Membership]::GeneratePassword($MinLength, $SpecialCharCount)
    }
}

function Stop-CCMService {
    #Stop Central Management components
    Stop-Service chocolatey-central-management
    Get-Process chocolateysoftware.chocolateymanagement.web* | Stop-Process -ErrorAction SilentlyContinue -Force
}

function Remove-CcmBinding {
    [CmdletBinding()]
    param()

    process {
        Write-Verbose "Removing existing bindings"
        netsh http delete sslcert ipport=0.0.0.0:443
    }
}

function New-CcmBinding {
    [CmdletBinding()]
    param()
    Write-Verbose "Adding new binding https://${SubjectWithoutCn} to Chocolatey Central Management"

    $guid = [Guid]::NewGuid().ToString("B")
    netsh http add sslcert ipport=0.0.0.0:443 certhash=$Thumbprint certstorename=MY appid="$guid"
    Get-WebBinding -Name ChocolateyCentralManagement | Remove-WebBinding
    New-WebBinding -Name ChocolateyCentralManagement -Protocol https -Port 443 -SslFlags 0 -IpAddress '*'
}

function Start-CcmService {
    try {
        Start-Service chocolatey-central-management -ErrorAction Stop
    }
    catch {
        #Try again...
        Start-Service chocolatey-central-management -ErrorAction SilentlyContinue
    }
    finally {
        if ((Get-Service chocolatey-central-management).Status -ne 'Running') {
            Write-Warning "Unable to start Chocolatey Central Management service, please start manually in Services.msc"
        }
    }

}

function Set-CcmCertificate {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [String]
        $CertificateThumbprint
    )

    process {
        Stop-Service chocolatey-central-management
        $jsonData = Get-Content $env:ChocolateyInstall\lib\chocolatey-management-service\tools\service\appsettings.json | ConvertFrom-Json
        $jsonData.CertificateThumbprint = $CertificateThumbprint
        $jsonData | ConvertTo-Json | Set-Content $env:chocolateyInstall\lib\chocolatey-management-service\tools\service\appsettings.json
        Start-Service chocolatey-central-management
    }
}

#endregion

#region README functions
function Remove-JsonFiles {
    <#
.SYNOPSIS
Removes unnecessary json data files from the system upon completion of the Quickstart Guide.
.PARAMETER JsonPath
The path to the JSON data files. Defaults to 'C:\choco-setup\logs'.
.EXAMPLE
./Start-C4bCleanup.ps1
.EXAMPLE
./Start-C4bCleanup.ps1 -JsonPath C:\Temp\
#>


    [CmdletBinding()]
    Param(
        [Parameter()]
        [String]
        $JsonPath = "$env:SystemDrive\choco-setup\logs"
    )

    process {

        Get-ChildItem $JsonPath  -Filter '*.json' | Foreach-Object { Remove-Item $_.FullName -Force }
    }
}

Function New-QuickstartReadme {
    <#
.SYNOPSIS
Generates a desktop README file containing service information for all services provisioned as part of the Quickstart Guide.
.PARAMETER HostName
The host name of the C4B instance.
.EXAMPLE
./New-QuickstartReadme.ps1
.EXAMPLE
./New-QuickstartReadme.ps1 -HostName c4b.example.com
#>
    [CmdletBinding()]
    Param(
        [Parameter()]
        [string]
        $HostName = $(Get-Content "$env:SystemDrive\choco-setup\logs\ssl.json" | ConvertFrom-Json).CertSubject

    )


    process {
        $nexusPassword = Get-Content -Path 'C:\ProgramData\sonatype-work\nexus3\admin.password'
        $jenkinsPassword = Get-Content -path 'C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword'
        $nexusApiKey = (Get-Content "$env:SystemDrive\choco-setup\logs\nexus.json" | ConvertFrom-Json).NuGetApiKey

        $tableData = @([pscustomobject]@{
                Name     = 'Nexus'
                Url      = "https://${HostName}:8443"
                Username = "admin"
                Password = $nexusPassword
                ApiKey   = $nexusApiKey
            },
            [pscustomobject]@{
                Name     = 'Central Management'
                Url      = "https://${HostName}"
                Username = "ccmadmin"
                Password = '123qwe'
            },
            [PSCustomObject]@{
                Name     = 'Jenkins'
                Url      = "http://${HostName}:8080"
                Username = "admin"
                Password = $jenkinsPassword
            }
        )


        $html = @"
    <html>
    <head>
    </head>
    <title>Chocolatey For Business Service Defaults</title>
    <style>
    table {
        border-collapse: collapse;
    }
    td,
    th {
        border: 0.1em solid rgba(0, 0, 0, 0.5);
        padding: 0.25em 0.5em;
        text-align: center;
    }
    blockquote {
        margin-left: 0.5em;
        padding-left: 0.5em;
        border-left: 0.1em solid rgba(0, 0, 0, 0.5);
    }</style>
    <body>
    <blockquote>
<p>📝 <strong>Note</strong></p>
<p>The following table provides the default credentials to login to each of the services made available as part of the Quickstart Guide setup process.</p> 
You'll be asked to change the credentials upon logging into each service for the first time.
Document your new credentials in a password manager, or whatever system you use.
</p>
</blockquote>
    $(($TableData | ConvertTo-Html -Fragment))
    </body>
    </html>
"@

        $folder = Join-Path $env:Public 'Desktop'
        $file = Join-Path $folder 'README.html'

        $html | Set-Content $file

    }
}
#endregion

#region Agent Setup
function Install-ChocolateyAgent {
    [CmdletBinding()]
    Param(
        [Parameter()]
        [String]
        $Source,

        [Parameter(Mandatory)]
        [String]
        $CentralManagementServiceUrl,

        [Parameter()]
        [String]
        $ServiceSalt,

        [Parameter()]
        [String]
        $ClientSalt
    )

    process {
        if ($Source) {
            $chocoArgs = @('install', 'chocolatey-agent', '-y', "--source='$Source'")
            & choco @chocoArgs
        }
        else {
            $chocoArgs = @('install', 'chocolatey-agent', '-y')
            & choco @chocoArgs
        }
        

        $chocoArgs = @('config', 'set', 'centralManagementServiceUrl', "$CentralManagementServiceUrl")
        & choco @chocoArgs

        $chocoArgs = @('feature', 'enable', '--name="useChocolateyCentralManagement"')
        & choco @chocoArgs

        $chocoArgs = @('feature', 'enable', '--name="useChocolateyCentralManagementDeployments"')
        & choco @chocoArgs

        if ($ServiceSalt -and $ClientSalt) {
            $chocoArgs = @('config', 'set', 'centralManagementClientCommunicationSaltAdditivePassword', "$ClientSalt")
            & choco @chocoArgs

            $chocoArgs = @('config', 'set', 'centralManagementServiceCommunicationSaltAdditivePassword', "$ServiceSalt")
            & choco @chocoArgs
        }
    }
}
#endregion