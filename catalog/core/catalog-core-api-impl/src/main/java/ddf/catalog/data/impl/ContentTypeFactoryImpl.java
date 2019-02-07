/**
 * Copyright (c) Codice Foundation
 *
 * <p>This is free software: you can redistribute it and/or modify it under the terms of the GNU
 * Lesser General Public License as published by the Free Software Foundation, either version 3 of
 * the License, or any later version.
 *
 * <p>This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details. A copy of the GNU Lesser General Public
 * License is distributed along with this program and can be found at
 * <http://www.gnu.org/licenses/lgpl.html>.
 */
package ddf.catalog.data.impl;

import ddf.catalog.data.ContentType;
import ddf.catalog.data.ContentTypeFactory;

import java.net.URI;

public class ContentTypeFactoryImpl implements ContentTypeFactory {

    @Override
    public ContentType getContentType() {
        return new ContentTypeImpl();
    }

    @Override
    public ContentType getContentType(String name, String version) {
        return new ContentTypeImpl(name, version);
    }

    @Override
    public ContentType getContentType(String name, String version, URI targetNamespace) {
        return new ContentTypeImpl(name, version, targetNamespace);
    }
}
