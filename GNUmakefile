#
# GNUmakefile - Generated by ProjectCenter
#
ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
  ifeq ($(GNUSTEP_MAKEFILES),)
    $(warning )
    $(warning Unable to obtain GNUSTEP_MAKEFILES setting from gnustep-config!)
    $(warning Perhaps gnustep-make is not properly installed,)
    $(warning so gnustep-config is not in your PATH.)
    $(warning )
    $(warning Your PATH is currently $(PATH))
    $(warning )
  endif
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

#
# Framework
#
VERSION = 0.9
PACKAGE_NAME = DataBasinKit
FRAMEWORK_NAME = DataBasinKit
DataBasinKit_CURRENT_VERSION_NAME = 0.9
DataBasinKit_DEPLOY_WITH_CURRENT_VERSION = yes


#
# Libraries
#
DataBasinKit_LIBRARIES_DEPEND_UPON += -lWebServices 

#
# Public headers (will be installed)
#
DataBasinKit_HEADER_FILES = \
DataBasinKit.h \
DBSoap.h \
DBSoapCSV.h \
DBSObject.h \
DBProgressProtocol.h \
DBLoggerProtocol.h \
DBCSVReader.h \
DBCSVWriter.h \
DBHTMLWriter.h \
DBFileWriter.h \
DBSFTypeWrappers.h 

#
# Objective-C Class files
#
DataBasinKit_OBJC_FILES = \
DBSoap.m \
DBSoapCSV.m \
DBSObject.m \
DBCSVReader.m \
DBCSVWriter.m \
DBHTMLWriter.m \
DBFileWriter.m \
DBSFTypeWrappers.m

#
# Makefiles
#
-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/aggregate.make
include $(GNUSTEP_MAKEFILES)/framework.make
-include GNUmakefile.postamble
