@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSupportsShouldProcess'
        'PSShouldProcess'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSUseSingularNouns'
}
