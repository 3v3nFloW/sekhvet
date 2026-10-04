/*=========================================================================
 This file is part of the Horos Project (www.horosproject.org)
 
 Horos is free software: you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published by
 the Free Software Foundation,  version 3 of the License.
 
 The Horos Project was based originally upon the OsiriX Project which at the time of
 the code fork was licensed as a LGPL project.  However, not all of the the source-code
 was properly documented and file headers were not all updated with the appropriate
 license terms. The Horos Project, originally was licensed under the  GNU GPL license.
 However, contributors to the software since that time have agreed to modify the license
 to the GNU LGPL in order to be conform to the changes previously made to the
 OsiriX Project.
 
 Horos is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY EXPRESS OR IMPLIED, INCLUDING ANY WARRANTY OF
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE OR USE.  See the
 GNU Lesser General Public License for more details.
 
 You should have received a copy of the GNU Lesser General Public License
 along with Horos.  If not, see http://www.gnu.org/licenses/lgpl.html
 
 Prior versions of this file were published by the OsiriX team pursuant to
 the below notice and licensing protocol.
 ============================================================================
 Program:   OsiriX
  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - LGPL
  
  See http://www.osirix-viewer.com/copyright.html for details.
     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
 ============================================================================*/
//
//  url.h
//  OsiriX_Lion
//
//  Created by Alex Bettarini on 22 Nov 2014.
//  Copyright (c) 2014 Osiri-LXIV Team. All rights reserved.
//

#ifndef URL_H_INCLUDED
#define URL_H_INCLUDED

// search for URLWithString
// SekhVet Paket CT: every link a user can reach goes to the SekhVet project page, none to horosproject.org.
// The macro names are kept because other source files use them.
#define URL_HOROS_VIEWER           @"https://github.com/3v3nFloW/sekhvet"
#define URL_HOROS_WEB_PAGE         URL_HOROS_VIEWER
#define URL_HOROS_BUG_REPORT_PAGE  URL_HOROS_VIEWER@"/issues"
#define URL_VENDOR                 URL_HOROS_VIEWER
#define URL_EMAIL                  @"sekhvet@kappa1.vet"

#define URL_VENDOR_NOTICE          URL_HOROS_VIEWER
#define URL_VENDOR_USER_MANUAL     URL_HOROS_VIEWER

#define URL_HOROS_DOC_SECURITY     URL_HOROS_VIEWER

#define URL_HOROS_PLUGINS          URL_HOROS_VIEWER

////////////////////////////////////////////////////////////////////////////////
// We want our own Defaults plist saved in ~/Library/Preferences/
// Make sure it matches "Bundle Identifier" in Info.plist
// SekhVet Paket CT: was the Horos identifier, so these macros pointed at the preferences of an installed Horos.

#define BUNDLE_IDENTIFIER_PREFIX    "vet.kappa1.sekhvet"
#define BUNDLE_IDENTIFIER           "vet.kappa1.sekhvet.horos"

////////////////////////////////////////////////////////////////////////////////
// SekhVet Paket CT: the remote plugin lists (plain http from horosproject.org) are no longer contacted.
// SekhVet has no plugin server; plugins are installed from a file the user already has.

#endif
