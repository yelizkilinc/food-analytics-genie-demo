<#
.SYNOPSIS
    Registers the Azure resource providers required by the sample.

.DESCRIPTION
    Reads the target subscription from deployment/environment.json, registers every
    provider used by the deployment, and waits until each provider is registered.
    The active Azure CLI subscription is not changed.
#>

[CmdletBinding()]
param(
    [string] $EnvironmentPath = (Join-Path $PSScriptRoot 'environment.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required. Install it and sign in before running this script.'
}

if (-not (Test-Path $EnvironmentPath)) {
    throw "Missing $EnvironmentPath. Copy deployment/environment.example.json to deployment/environment.json and set SubscriptionId."
}

$environment = Get-Content -Path $EnvironmentPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($environment.SubscriptionId) -or $environment.SubscriptionId -match '<[^>]+>') {
    throw "Set SubscriptionId in $EnvironmentPath before running this script."
}

$providers = @(
    'Microsoft.App'
    'Microsoft.CognitiveServices'
    'Microsoft.Compute'
    'Microsoft.ContainerRegistry'
    'Microsoft.ContainerService'
    'Microsoft.Databricks'
    'Microsoft.DocumentDB'
    'Microsoft.KeyVault'
    'Microsoft.Network'
    'Microsoft.Search'
    'Microsoft.Storage'
)

az account show --subscription $environment.SubscriptionId --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI cannot access subscription '$($environment.SubscriptionId)'. Sign in to the correct tenant and try again."
}

foreach ($provider in $providers) {
    $state = az provider show `
        --namespace $provider `
        --subscription $environment.SubscriptionId `
        --query registrationState `
        --output tsv `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Could not read registration state for resource provider '$provider'."
    }

    if ($state -ne 'Registered') {
        Write-Host "Registering $provider..."
        az provider register `
            --namespace $provider `
            --subscription $environment.SubscriptionId `
            --wait `
            --only-show-errors

        if ($LASTEXITCODE -ne 0) {
            throw "Resource provider registration failed for '$provider'."
        }
    }
}

$notRegistered = @(
    foreach ($provider in $providers) {
        $state = az provider show `
            --namespace $provider `
            --subscription $environment.SubscriptionId `
            --query registrationState `
            --output tsv `
            --only-show-errors

        if ($LASTEXITCODE -ne 0 -or $state -ne 'Registered') {
            "$provider ($state)"
        }
    }
)

if ($notRegistered.Count -gt 0) {
    throw "These resource providers are not registered: $($notRegistered -join ', ')"
}

Write-Host "All required resource providers are registered in subscription '$($environment.SubscriptionId)'."
