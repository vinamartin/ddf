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
package org.codice.ddf.persistence.events;

import static org.hamcrest.CoreMatchers.equalTo;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.mockito.Matchers.any;
import static org.mockito.Matchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ScheduledExecutorService;

import org.codice.ddf.persistence.PersistentItem;
import org.codice.ddf.persistence.PersistentStore;
import org.codice.ddf.system.alerts.Alert;
import org.codice.ddf.system.alerts.PeriodicAlert;
import org.codice.ddf.system.alerts.SystemNotice;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.osgi.service.event.Event;
import org.osgi.service.event.EventAdmin;

public class AlertListenerTest {

    private PersistentStore persistentStore;

    private EventAdmin eventAdmin;

    private ScheduledExecutorService executorService;

    private AlertListener alertListener;

    @Before
    public void setup() {
        persistentStore = mock(PersistentStore.class);
        eventAdmin = mock(EventAdmin.class);
        executorService = mock(ScheduledExecutorService.class);

        alertListener = new AlertListener(persistentStore, eventAdmin, executorService);
    }

    @Test
    public void testHandleEvenFirstAlert() throws Exception {
        SystemNotice notice = new SystemNotice("test-source", 3, "title", new HashSet());
        Alert alert = new Alert();
        alert.putAll(notice);
        alert.put("event.topics", "decanter/alert/test");

        ArgumentCaptor<Event> captor = ArgumentCaptor.forClass(Event.class);

        Event event = new Event("decanter/alert/test", notice);
        when(persistentStore.get(any(), any())).thenReturn(new ArrayList<>());
        alertListener.handleEvent(event);
        verify(persistentStore).add(eq("alerts"), any(PersistentItem.class));
        verify(eventAdmin).postEvent(captor.capture());
        List<Alert> alertList = (List<Alert>) captor.getValue()
                .getProperty(PeriodicAlert.ALERTS_KEY);
        assertThat(alertList.size(), equalTo(1));
        for (Map.Entry entry : notice.entrySet()) {
            assertThat(alertList.get(0)
                    .get(entry.getKey()), equalTo(entry.getValue()));
        }
        assertThat(alertList.get(0)
                .get(Alert.ALERT_STATUS), equalTo(Alert.ALERT_ACTIVE_STATUS));
    }

    @Test
    public void testHandleEvenExistingAlert() throws Exception {
        Alert alert = new Alert("test-source", 3, "title", new HashSet());
        alert.put("event.topics", "decanter/alert/test");
        alert.put(Alert.ALERT_STATUS, Alert.ALERT_ACTIVE_STATUS);
        ArgumentCaptor<PersistentItem> captor = ArgumentCaptor.forClass(PersistentItem.class);

        Event event = new Event("decanter/alert/test", alert);
        when(persistentStore.get(any(),
                any())).thenReturn(Collections.singletonList(toSolr(alert)));
        alertListener.handleEvent(event);
        verify(persistentStore).add(eq("alerts"), captor.capture());
        verify(eventAdmin, never()).postEvent(any());
        PersistentItem item = captor.getValue();
        assertThat(item.getLongProperty(Alert.ALERT_COUNT), equalTo(2L));
    }

    @Test
    public void testHandleNonSystemNoticeAlert() throws Exception {
        ArgumentCaptor<Event> captor = ArgumentCaptor.forClass(Event.class);
        Map<String, String> genericAlert = new HashMap<>();
        genericAlert.put("property1", "value1");
        genericAlert.put(Alert.SYSYTEM_NOTICE_SOURCE_KEY, "source");
        when(persistentStore.get(any(), any())).thenReturn(new ArrayList<>());
        Event event = new Event("decanter/alert/test", genericAlert);
        alertListener.handleEvent(event);

        verify(persistentStore).add(eq("alerts"), any(PersistentItem.class));
        verify(eventAdmin).postEvent(captor.capture());
        List<Alert> alertList = (List<Alert>) captor.getValue()
                .getProperty(PeriodicAlert.ALERTS_KEY);
        assertThat(alertList.size(), equalTo(1));
        for (Map.Entry entry : genericAlert.entrySet()) {
            assertThat(alertList.get(0)
                    .get(entry.getKey()), equalTo(entry.getValue()));
        }
        assertThat(alertList.get(0)
                .get(Alert.ALERT_STATUS), equalTo(Alert.ALERT_ACTIVE_STATUS));
    }

    @Test
    public void testHandleInvalidNonSystemNoticeAlert() throws Exception {
        Map<String, String> genericAlert = new HashMap<>();
        genericAlert.put("property1", "value1");

        when(persistentStore.get(any(), any())).thenReturn(new ArrayList<>());
        Event event = new Event("decanter/alert/test", genericAlert);
        alertListener.handleEvent(event);

        verify(persistentStore, never()).add(eq("alerts"), any(PersistentItem.class));
        verify(eventAdmin, never()).postEvent(any());
    }

    @Test
    public void testHandleEventDismiss() throws Exception {
        Alert alert = new Alert("test-source", 3, "title", new HashSet());
        ArgumentCaptor<PersistentItem> captor = ArgumentCaptor.forClass(PersistentItem.class);
        Map<String, String> dismissEvent = new HashMap<>();
        dismissEvent.put(Alert.SYSYTEM_NOTICE_ID_KEY, alert.getId());
        dismissEvent.put(Alert.ALERT_DISMISSED_BY, "test-user");
        Event event = new Event(Alert.ALERT_DISMISS_TOPIC, dismissEvent);
        when(persistentStore.get(any(),
                any())).thenReturn(Collections.singletonList(toSolr(alert)));
        alertListener.handleEvent(event);
        verify(persistentStore).add(eq("alerts"), captor.capture());
        verify(eventAdmin, never()).postEvent(any());
        PersistentItem item = captor.getValue();
        assertThat(item.getTextProperty(Alert.ALERT_DISMISSED_BY), equalTo("test-user"));
        assertThat(item.getTextProperty(Alert.ALERT_STATUS), equalTo(Alert.ALERT_DISMISSED_STATUS));
    }

    @Test
    public void testHandleEvenDismissNoId() throws Exception {
        Map<String, String> dismissEvent = new HashMap<>();
        dismissEvent.put(Alert.ALERT_DISMISSED_BY, "test-user");
        Event event = new Event(Alert.ALERT_DISMISS_TOPIC, dismissEvent);
        alertListener.handleEvent(event);
        verify(persistentStore, never()).add(any(), any(PersistentItem.class));
        verify(eventAdmin, never()).postEvent(any());
    }

    @Test
    public void testHandleEvenDismissBadId() throws Exception {
        Map<String, String> dismissEvent = new HashMap<>();
        dismissEvent.put(Alert.SYSYTEM_NOTICE_ID_KEY, "bad-id");
        dismissEvent.put(Alert.ALERT_DISMISSED_BY, "test-user");
        Event event = new Event(Alert.ALERT_DISMISS_TOPIC, dismissEvent);
        when(persistentStore.get(any(), any())).thenReturn(new ArrayList<>());
        alertListener.handleEvent(event);
        verify(persistentStore, never()).add(any(), any(PersistentItem.class));
        verify(eventAdmin, never()).postEvent(any());
    }

    @Test
    public void testHandleEvenDismissNoDismissedBy() throws Exception {
        SystemNotice alert = new SystemNotice("test-source", 3, "title", new HashSet());
        ArgumentCaptor<PersistentItem> captor = ArgumentCaptor.forClass(PersistentItem.class);
        Map<String, String> dismissEvent = new HashMap<>();
        dismissEvent.put(Alert.SYSYTEM_NOTICE_ID_KEY, alert.getId());
        Event event = new Event(Alert.ALERT_DISMISS_TOPIC, dismissEvent);
        when(persistentStore.get(any(),
                any())).thenReturn(Collections.singletonList(toSolr(alert)));
        alertListener.handleEvent(event);
        verify(persistentStore, never()).add(any(), any(PersistentItem.class));
        verify(eventAdmin, never()).postEvent(any());
    }

    private Map<String, Object> toSolr(SystemNotice alert) {
        Map<String, Object> map = new HashMap<>();
        for (Map.Entry entry : alert.entrySet()) {
            map.put(entry.getKey() + "_txt", entry.getValue());
        }
        return map;
    }

}
