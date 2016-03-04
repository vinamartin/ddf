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
package ddf.test.itests.catalog;

import static org.junit.Assert.fail;
import static com.jayway.restassured.RestAssured.given;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import javax.ws.rs.core.MediaType;

import org.apache.karaf.jaas.boot.principal.RolePrincipal;
import org.apache.shiro.mgt.DefaultSecurityManager;
import org.apache.shiro.subject.PrincipalCollection;
import org.apache.shiro.subject.SimplePrincipalCollection;
import org.codice.ddf.security.policy.context.impl.PolicyManager;
import org.hamcrest.xml.HasXPath;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.ops4j.pax.exam.junit.PaxExam;
import org.ops4j.pax.exam.spi.reactors.ExamReactorStrategy;
import org.ops4j.pax.exam.spi.reactors.PerClass;

import com.jayway.restassured.response.ValidatableResponse;

import ddf.catalog.data.Metacard;
import ddf.catalog.data.impl.BasicTypes;
import ddf.catalog.data.impl.MetacardImpl;
import ddf.catalog.operation.CreateRequest;
import ddf.catalog.operation.CreateResponse;
import ddf.catalog.operation.impl.CreateRequestImpl;
import ddf.common.test.BeforeExam;
import ddf.security.SecurityConstants;
import ddf.security.Subject;
import ddf.security.common.util.Security;
import ddf.security.impl.SubjectImpl;
import ddf.test.itests.AbstractIntegrationTest;
import ddf.test.itests.common.CswQueryBuilder;
import ddf.test.itests.common.Library;

@RunWith(PaxExam.class)
@ExamReactorStrategy(PerClass.class)
public class TestRegistry extends AbstractIntegrationTest {

    private static final String CATALOG_REGISTRY = "catalog-registry";

    private static final String CATALOG_STORE_ID = "cswCatalogStoreSource";

    @BeforeExam
    public void beforeExam() throws Exception {
        try {
            basePort = getBasePort();
            getAdminConfig().setLogLevels();
            getServiceManager().waitForRequiredApps(getDefaultRequiredApps());
            getServiceManager().waitForAllBundles();
            getCatalogBundle().waitForCatalogProvider();
            getServiceManager().waitForHttpEndpoint(SERVICE_ROOT + "/catalog/query?_wadl");

            CswCatalogStoreProperties cswCatalogStoreProperties = new CswCatalogStoreProperties(
                    CATALOG_STORE_ID);
            getServiceManager().createManagedService(cswCatalogStoreProperties.FACTORY_PID,
                    cswCatalogStoreProperties);
            //            getCatalogBundle().waitForFederatedSource(CATALOG_STORE_ID);
            getCatalogBundle().waitForCatalogStore(CATALOG_STORE_ID);

        } catch (Exception e) {
            LOGGER.error("Failed in @BeforeExam: ", e);
            fail("Failed in @BeforeExam: " + e.getMessage());
        }
    }

    @Test
    public void testCswRegistryIngest() throws Exception {
        getServiceManager().startFeature(true, CATALOG_REGISTRY);
        given().body(Library.getCswRegistryInsert())
                .header("Content-Type", "text/xml")
                .expect()
                .log()
                .all()
                .statusCode(200)
                .when()
                .post(CSW_PATH.getUrl())
                .getHeader("id");

    }

    @Test
    public void testCswRegistryCreate() throws Exception {
        ArrayList<Metacard> metacards = new ArrayList<>();
        Map<String, Serializable> properties = new HashMap<>();
        Set<String> destinations = new HashSet<>();

        MetacardImpl metacard = new MetacardImpl(BasicTypes.BASIC_METACARD);
        metacard.setId("metacard1");
        metacards.add(metacard);
        properties.put(metacard.getId(), metacard);

        org.apache.shiro.mgt.SecurityManager securityManager = new DefaultSecurityManager();
        PrincipalCollection principals = new SimplePrincipalCollection(new RolePrincipal("guest"),
                PolicyManager.DEFAULT_REALM);

        Subject subject = new SubjectImpl(principals, true, null, securityManager);

        properties.put(SecurityConstants.SECURITY_SUBJECT, Security.getSystemSubject());

        destinations.add(CATALOG_STORE_ID);

        CreateRequest createRequest = new CreateRequestImpl(metacards, properties, destinations);
        CreateResponse createResponse = getCatalogBundle().getCatalogFramework()
                .create(createRequest);

        String query =
                new CswQueryBuilder().addAttributeFilter(CswQueryBuilder.PROPERTY_IS_EQUAL_TO,
                        Metacard.ID,
                        "metacard1")
                        .getQuery();

        ValidatableResponse response = given().auth()
                .preemptive()
                .basic("admin", "admin")
                .header("Content-Type", MediaType.APPLICATION_XML)
                .body(query)
                .post(CSW_PATH.getUrl())
                .then();

        response.body(HasXPath.hasXPath(String.format(
                "/GetRecordsResponse/SearchResults/Record[identifier=\"%s\"]",
                "metacard1")));
    }



}
