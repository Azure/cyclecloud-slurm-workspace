Pre-requisite: 
* The Bicep CLI must be installed manually (*i.e.*, separately from the az CLI) per the instructions available [here](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install#install-manually)

Tests should be specific to files in the bicep direcitory and added as follows: 
* All bicep files with components to be tested should have a corresponding [bicep file name]-test.bicep file in the bicep-test directory
    * For example, the test file for bicep/network-new.bicep is bicep-test/network-new-test.bicep
* References to the [bicep file name]-test.bicep files should be added as a test block in bicep-test/test.bicep per the second item listed [here](https://github.com/Azure/bicep/issues/11967)
    
Rationale: The Partner Center proscribes the use of experimental features such as testing and assertions because they require on ARM 2.0 language support. This procedure circumvents the Partner Center and stops the ARM template build process in the event of failed tests. 

Tests may be ran in one of two manners: 
1. Running the build script, *i.e.*, ```build.sh```
2. Using ```bicep test``` as documented [here](https://github.com/Azure/bicep/issues/11967)
    * For example, ```bicep test ./bicep-test/test.bicep```