#Solr

###Introduction
Every file needed to run a particular version of Solr is packaged into the DDF
distribution. A plain Solr distribution (.zip) is downloaded by a maven plugin. DDF-specific 
files or changes to base Solr files are defined in the **solr-distro** module, in the 
`solr-distro/solr-custom-files` directory.

The operations defined in the **solr-distro** POM are bound the the `prepare-package` 
lifecycle phase. This is because the artifact created by **solr-distro** is used by the integration tests. The integration tests unpack the artifact and start the Solr process
as part of the `package` and `pre-integration-test` lifecycle phases.
See the POM.xml file for the **test-itests-ddf** module for details.

### Downloading the Solr distribution
Downloading the Solr distribution is performed by the download-maven-plugin. See the 
modules's POM.xml file for configuration. The download URL is a literal string,
expect for the maven property `${solr.version)`. The download-maven-plugin
is also configured with the sha1 hash for the distribution file. The download operation
shoud fail if the the file's sha1 does not match the configured value. This is done 
for protection against false or corrupted Solr distributions.

Changing the version of Solr that is download can be as simple as updating the 
`${solr.version}` property and changing the sha1 hash in the POM.xml file. However, 
the literal URL might be to be changed as well. For example, if `archive.apache.org` no longer hosts the zip file.

The download-maven-plugin will cache the Solr distribution zip file in the local maven 
repository. 

### Creating the DDF custom Solr distribution
Files that should be different from the base Solr distribution, or are needed in addition
to the base Solr files should be places in the `solr-distro/solr-custom-files` 
directory. The maven-assembly-plugin will copy those files into modules's `target` (output)
directory. Then the maven-assembly-plugin will unzip the Solr distribution into the 
module's target directory. It is done in this order. The maven-assembly-plugin does NOT
overwrite files, so the DDF custom files must be copied first. 

Finally, the maven-assembly-plugin creates a type `zip` artifact and assigns it the 
classifier `assembly`. This artifact is installed into the local repository where the 
integration tests can access it.

## The maven-assembly-plugin descriptor file
The maven-assembly-plugin's instructions are not in the POM.xml file. They are in a 
maven-assembly-plugin descriptor file. The descriptor file is `solr-distro/assemblyl.xml`. 