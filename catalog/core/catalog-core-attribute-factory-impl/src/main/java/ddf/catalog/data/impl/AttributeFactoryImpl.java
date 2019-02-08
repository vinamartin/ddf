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

import ddf.catalog.data.Attribute;
import ddf.catalog.data.AttributeFactory;
import java.io.Serializable;
import java.util.List;

public class AttributeFactoryImpl implements AttributeFactory {
  @Override
  public Attribute getAttribute(String name, Serializable value) {
    return new AttributeImpl(name, value);
  }

  @Override
  public Attribute getAttribute(String name, List<Serializable> values) {
    return new AttributeImpl(name, values);
  }

  @Override
  public Attribute getAttribute(Attribute attribute) {
    return new AttributeImpl(attribute);
  }
}
