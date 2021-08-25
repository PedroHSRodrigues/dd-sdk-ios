Pod::Spec.new do |s|
  s.name         = "DatadogSDKCrashReporting"
  s.module_name  = "DatadogCrashReporting"
  s.version      = "1.7.0-beta3"
  s.summary      = "Official Datadog Crash Reporting SDK for iOS."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = { 
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Mert Buran" => "mert.buran@datadoghq.com"
  }

  s.swift_version      = '5.1'
  s.ios.deployment_target = '10.0'

  s.source = { :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => s.version.to_s }

  s.source_files = "Sources/DatadogCrashReporting/**/*.swift"
  s.dependency 'DatadogSDK', '1.7.0-beta3'
  s.dependency 'PLCrashReporter', '~> 1.8.1'
end
