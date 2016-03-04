/**
 * Copyright (c) Codice Foundation
 * <p>
 * This is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser
 * General Public License as published by the Free Software Foundation, either version 3 of the
 * License, or any later version.
 * <p>
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
 * even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details. A copy of the GNU Lesser General Public License
 * is distributed along with this program and can be found at
 * <http://www.gnu.org/licenses/lgpl.html>.
 */
package org.codice.ddf.spatial.ogc.csw.catalog.endpoint.reader;

import static org.custommonkey.xmlunit.XMLAssert.assertXpathEvaluatesTo;
import static org.custommonkey.xmlunit.XMLAssert.assertXpathExists;
import static org.mockito.Mockito.mock;

import static junit.framework.Assert.assertTrue;

import java.io.IOException;
import java.util.Arrays;
import java.util.HashMap;

import org.codice.ddf.spatial.ogc.csw.catalog.common.CswConstants;
import org.codice.ddf.spatial.ogc.csw.catalog.common.transaction.CswTransactionRequest;
import org.codice.ddf.spatial.ogc.csw.catalog.common.transaction.InsertAction;
import org.custommonkey.xmlunit.Diff;
import org.custommonkey.xmlunit.SimpleNamespaceContext;
import org.custommonkey.xmlunit.XMLAssert;
import org.custommonkey.xmlunit.XMLUnit;
import org.custommonkey.xmlunit.XpathEngine;
import org.custommonkey.xmlunit.exceptions.XpathException;
import org.junit.BeforeClass;
import org.junit.Test;
import org.w3c.dom.Document;
import org.xml.sax.SAXException;

import com.thoughtworks.xstream.XStream;
import com.thoughtworks.xstream.converters.Converter;
import com.thoughtworks.xstream.io.xml.Xpp3Driver;

import ddf.catalog.data.Metacard;
import ddf.catalog.data.impl.MetacardImpl;

public class TestTransactionRequestConverter {

    String expectedXML =
            "<csw:Transaction service=\"CSW\" version=\"2.0.2\" verboseResponse=\"true\" xmlns:csw=\"http://www.opengis.net/cat/csw/2.0.2\">\n"
                    + "  <csw:Insert typeName=\"ebrim\"/>\n" + "</csw:Transaction>";

    @Test
    public void testValidMarshal() throws SAXException, IOException, XpathException {
        Converter cswRecordConverter = mock(Converter.class);

        XStream xStream = new XStream(new Xpp3Driver());
        xStream.registerConverter(new TransactionRequestConverter(cswRecordConverter));
        xStream.alias("csw:" + CswConstants.TRANSACTION, CswTransactionRequest.class);

        CswTransactionRequest transactionRequest = new CswTransactionRequest();
        MetacardImpl metacard = new MetacardImpl();
        metacard.setId("metacard1");
        InsertAction insertAction = new InsertAction("ebrim", null, Arrays.asList(metacard));
        transactionRequest.getInsertActions()
                .add(insertAction);
        transactionRequest.setService(CswConstants.CSW);
        transactionRequest.setVerbose(true);
        transactionRequest.setVersion(CswConstants.VERSION_2_0_2);

        String xml = xStream.toXML(transactionRequest);
        Diff diff = XMLUnit.compareXML(xml, expectedXML);
        assertTrue(diff.similar());
    }
}
