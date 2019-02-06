package ddf.catalog.data.impl;

import java.io.Serializable;
import java.util.List;

import ddf.catalog.data.Attribute;
import ddf.catalog.data.types.AttributeFactory;

public class AttributeFactoryImpl implements AttributeFactory{
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
