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

package org.codice.ddf.catalog.admin.poller;

import static org.hamcrest.Matchers.hasItems;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertThat;
import static org.junit.Assert.assertTrue;
import static org.mockito.Matchers.any;
import static org.mockito.Matchers.anyMap;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.io.IOException;
import java.io.Serializable;
import java.net.URI;
import java.util.ArrayList;
import java.util.Dictionary;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.apache.shiro.util.CollectionUtils;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mock;
import org.osgi.service.cm.Configuration;
import org.osgi.service.cm.ConfigurationAdmin;

import ddf.catalog.CatalogFramework;
import ddf.catalog.data.ContentType;
import ddf.catalog.data.Metacard;
import ddf.catalog.data.Result;
import ddf.catalog.data.impl.AttributeImpl;
import ddf.catalog.data.impl.MetacardImpl;
import ddf.catalog.data.impl.ResultImpl;
import ddf.catalog.federation.FederationException;
import ddf.catalog.filter.FilterBuilder;
import ddf.catalog.filter.proxy.builder.GeotoolsFilterBuilder;
import ddf.catalog.operation.CreateRequest;
import ddf.catalog.operation.CreateResponse;
import ddf.catalog.operation.DeleteRequest;
import ddf.catalog.operation.DeleteResponse;
import ddf.catalog.operation.QueryRequest;
import ddf.catalog.operation.ResourceResponse;
import ddf.catalog.operation.SourceResponse;
import ddf.catalog.operation.UpdateRequest;
import ddf.catalog.operation.UpdateResponse;
import ddf.catalog.operation.impl.QueryRequestImpl;
import ddf.catalog.operation.impl.QueryResponseImpl;
import ddf.catalog.registry.api.metacard.RegistryObjectMetacardType;
import ddf.catalog.resource.ResourceNotFoundException;
import ddf.catalog.resource.ResourceNotSupportedException;
import ddf.catalog.service.ConfiguredService;
import ddf.catalog.source.CatalogStore;
import ddf.catalog.source.IngestException;
import ddf.catalog.source.Source;
import ddf.catalog.source.SourceMonitor;
import ddf.catalog.source.SourceUnavailableException;
import ddf.catalog.source.UnsupportedQueryException;
import ddf.catalog.source.opensearch.OpenSearchSource;

public class AdminPollerTest {

    public static final String CONFIG_PID = "properPid";

    public static final String EXCEPTION_PID = "throwsAnException";

    public static final String FPID = "OpenSearchSource";

    public static MockedAdminPoller poller;

    @Mock
    private CatalogFramework catalogFramework;

    private FilterBuilder filterBuilder;

    private Map<String, CatalogStore> catalogStoreMap;

    @Before
    public void setup() {
        catalogFramework = mock(CatalogFramework.class);
        catalogStoreMap = new HashMap<>();
        catalogStoreMap.put("destination1", new MockCatalogStore("destination1", true));
        catalogStoreMap.put("destination2", new MockCatalogStore("destination2", true));
        catalogStoreMap.put("destination3", new MockCatalogStore("destination3", true));

        filterBuilder = new GeotoolsFilterBuilder();

        poller = new AdminPollerTest().new MockedAdminPoller(null,
                catalogFramework,
                filterBuilder,
                catalogStoreMap);
    }

    @Test
    public void testAllSourceInfo() {
        List<Map<String, Object>> sources = poller.allMetatypeInfo();
        assertNotNull(sources);
        assertEquals(2, sources.size());

        assertFalse(sources.get(0)
                .containsKey("configurations"));
        assertTrue(sources.get(1)
                .containsKey("configurations"));
    }

    @Test
    public void testSourceStatus() {
        assertTrue(poller.sourceStatus(CONFIG_PID));
        assertFalse(poller.sourceStatus(EXCEPTION_PID));
        assertFalse(poller.sourceStatus("FAKE SOURCE"));
    }

    @Test
    public void testPublish()
            throws UnsupportedQueryException, SourceUnavailableException, FederationException,
            IngestException {
        List<Metacard> metacards = new ArrayList<>();
        ArrayList<String> publishedPlaces = new ArrayList<>();
        publishedPlaces.add("destination1");
        publishedPlaces.add("destination3");
        ArrayList<String> destinations = new ArrayList<>();
        destinations.add("destination1");
        destinations.add("destination2");

        Metacard metacard1 = new MetacardImpl();
        metacard1.setAttribute(new AttributeImpl(RegistryObjectMetacardType.PUBLISHED_LOCATIONS,
                publishedPlaces));
        Metacard metacard2 = new MetacardImpl();
        metacard2.setAttribute(new AttributeImpl(RegistryObjectMetacardType.PUBLISHED_LOCATIONS,
                publishedPlaces));

        List<Result> results = new ArrayList<>();
        results.add(new ResultImpl(metacard1));
        when(catalogFramework.query(any())).thenReturn(new QueryResponseImpl(new QueryRequestImpl(
                null), results, 1));

        List<Serializable> newPublishedPlaces = poller.publish("mySource", destinations);
        assertThat(newPublishedPlaces, hasItems("destination1", "destination2"));
        assertFalse(newPublishedPlaces.contains("destination3"));
    }

    public static class MockCatalogStore implements CatalogStore {
        private Map<String, Set<String>> attributes = new HashMap<>();

        private String id;

        private Boolean isAvailable;

        public MockCatalogStore(String id, boolean isAvailable,
                Map<String, Set<String>> attributes) {
            this(id, isAvailable);
            this.attributes = attributes;
        }

        public MockCatalogStore(String id, boolean isAvailable) {
            this.id = id;
            this.isAvailable = isAvailable;
        }

        @Override
        public boolean isAvailable() {
            return false;
        }

        @Override
        public boolean isAvailable(SourceMonitor callback) {
            return false;
        }

        @Override
        public SourceResponse query(QueryRequest request) throws UnsupportedQueryException {
            return null;
        }

        @Override
        public Set<ContentType> getContentTypes() {
            return null;
        }

        @Override
        public Map<String, Set<String>> getSecurityAttributes() {
            return attributes;
        }

        @Override
        public CreateResponse create(CreateRequest createRequest) throws IngestException {
            return null;
        }

        @Override
        public UpdateResponse update(UpdateRequest updateRequest) throws IngestException {
            return null;
        }

        @Override
        public DeleteResponse delete(DeleteRequest deleteRequest) throws IngestException {
            return null;
        }

        @Override
        public ResourceResponse retrieveResource(URI uri, Map<String, Serializable> arguments)
                throws IOException, ResourceNotFoundException, ResourceNotSupportedException {
            return null;
        }

        @Override
        public Set<String> getSupportedSchemes() {
            return null;
        }

        @Override
        public Set<String> getOptions(Metacard metacard) {
            return null;
        }

        @Override
        public String getVersion() {
            return null;
        }

        @Override
        public String getId() {
            return null;
        }

        @Override
        public String getTitle() {
            return null;
        }

        @Override
        public String getDescription() {
            return null;
        }

        @Override
        public String getOrganization() {
            return null;
        }
    }

    private class MockedAdminPoller extends AdminPollerServiceBean {
        public MockedAdminPoller(ConfigurationAdmin configAdmin, CatalogFramework catalogFramework,
                FilterBuilder filterBuilder, Map<String, CatalogStore> catalogStoreMap) {
            super(configAdmin, catalogFramework, filterBuilder, catalogStoreMap);
        }

        @Override
        protected AdminSourceHelper getHelper() {
            AdminSourceHelper helper = mock(AdminSourceHelper.class);
            try {
                // Mock out the configuration
                Configuration config = mock(Configuration.class);
                when(config.getPid()).thenReturn(CONFIG_PID);
                when(config.getFactoryPid()).thenReturn(FPID);
                Dictionary<String, Object> dict = new Hashtable<>();
                dict.put("service.pid", CONFIG_PID);
                dict.put("service.factoryPid", FPID);
                when(config.getProperties()).thenReturn(dict);
                when(helper.getConfigurations(anyMap())).thenReturn(CollectionUtils.asList(config),
                        null);

                // Mock out the sources
                OpenSearchSource source = mock(OpenSearchSource.class);
                when(source.isAvailable()).thenReturn(true);

                OpenSearchSource badSource = mock(OpenSearchSource.class);
                when(badSource.isAvailable()).thenThrow(new RuntimeException());

                //CONFIG_PID, EXCEPTION_PID, FAKE_SOURCE
                when(helper.getConfiguration(any(ConfiguredService.class))).thenReturn(config,
                        config,
                        config);
                when(helper.getSources()).thenReturn(CollectionUtils.asList((Source) source,
                        badSource));

                // Mock out the metatypes
                Map<String, Object> metatype = new HashMap<>();
                metatype.put("id", "OpenSearchSource");
                metatype.put("metatype", new ArrayList<Map<String, Object>>());

                Map<String, Object> noConfigMetaType = new HashMap<>();
                noConfigMetaType.put("id", "No Configurations");
                noConfigMetaType.put("metatype", new ArrayList<Map<String, Object>>());

                when(helper.getMetatypes()).thenReturn(CollectionUtils.asList(metatype,
                        noConfigMetaType));
            } catch (Exception e) {

            }

            return helper;
        }
    }
}
