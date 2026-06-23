@{
    # CI und lokales Invoke-LocalCI: nur Errors blockieren.
    Severity     = @('Error')
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSupportsShouldProcess'
        'PSShouldProcess'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSUseSingularNouns'
    )
}
