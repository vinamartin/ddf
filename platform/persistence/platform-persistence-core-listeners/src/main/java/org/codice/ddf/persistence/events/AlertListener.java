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

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

import org.codice.ddf.persistence.PersistenceException;
import org.codice.ddf.persistence.PersistentItem;
import org.codice.ddf.persistence.PersistentStore;
import org.codice.ddf.system.alerts.Alert;
import org.codice.ddf.system.alerts.PeriodicAlert;
import org.osgi.service.event.Event;
import org.osgi.service.event.EventAdmin;
import org.osgi.service.event.EventHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class AlertListener implements EventHandler {

    private static final String CORE_NAME = "alerts";

    private static final Logger LOGGER = LoggerFactory.getLogger(AlertListener.class);

    private PersistentStore persistentStore;

    private EventAdmin eventAdmin;

    private ScheduledExecutorService executorService;

    private String hostName;

    private long period = TimeUnit.HOURS.toMinutes(24L);

    private ScheduledFuture scheduledFuture;

    public AlertListener(PersistentStore persistentStore, EventAdmin eventAdmin,
            ScheduledExecutorService executorService) {
        this.persistentStore = persistentStore;
        this.eventAdmin = eventAdmin;
        this.executorService = executorService;
        try {
            hostName = InetAddress.getLocalHost()
                    .getHostName();
        } catch (UnknownHostException e) {
            LOGGER.warn("Could not get localhost name.");
        }

        scheduledFuture = executorService.scheduleAtFixedRate(this::firePeriodicEvent,
                period,
                period,
                TimeUnit.MINUTES);
    }

    public void destroy() {
        executorService.shutdown();
    }

    /**
     * Processes alert events and stores them in the persistent store. Because this handler 'squashes'
     * alerts into one entry it needs to be synchronized to be thread safe.
     *
     * @param event The osgi alert event
     * @throws IllegalArgumentException
     */
    @Override
    public synchronized void handleEvent(Event event) throws IllegalArgumentException {
        if (Alert.ALERT_DISMISS_TOPIC.equals(event.getTopic())) {
            dismissAlert(event);
            return;
        }
        //need source to lookup previous alerts
        if (event.getProperty(Alert.SYSYTEM_NOTICE_SOURCE_KEY) == null) {
            return;
        }
        LOGGER.debug("Received alert event on topic {}", event.getTopic());

        Alert alert = getAlertFromEvent(event);
        Alert existingAlert = getAlertBySource(alert.getSource());
        if (existingAlert != null) {
            existingAlert.setCount(existingAlert.getCount() + 1);
            existingAlert.setLastUpdated(alert.getTime());
            existingAlert.setDetails(alert.getDetails());
            alert = existingAlert;
        } else {
            //first time we see an alert fire an event on the periodic topic
            eventAdmin.postEvent(new Event(PeriodicAlert.PERIODIC_TOPIC, new PeriodicAlert(
                    Collections.singletonList(alert))));
        }

        addAlertToStore(alert);
    }

    private void addAlertToStore(Alert alert) {
        PersistentItem item = new PersistentItem();
        item.addIdProperty(alert.getId());
        item.addProperty(Alert.SYSYTEM_NOTICE_SOURCE_KEY, alert.getSource());
        item.addProperty(Alert.SYSYTEM_NOTICE_HOST_NAME_KEY, alert.getHostName());
        item.addProperty(Alert.SYSYTEM_NOTICE_HOST_ADDRESS_KEY, alert.getHostAddress());
        item.addProperty(Alert.SYSYTEM_NOTICE_PRIORITY_KEY, alert.getPriority());
        item.addProperty(Alert.SYSYTEM_NOTICE_TITLE_KEY, alert.getTitle());
        item.addProperty(Alert.SYSYTEM_NOTICE_DETAILS_KEY, alert.getDetails());
        item.addProperty(Alert.SYSYTEM_NOTICE_TIME_KEY, alert.getTime());
        item.addProperty(Alert.ALERT_STATUS, alert.getStatus());
        item.addProperty(Alert.ALERT_LAST_UPDATED, alert.getLastUpdated());
        item.addProperty(Alert.ALERT_COUNT, alert.getCount());

        if (alert.getDismissedBy() != null) {
            item.addProperty(Alert.ALERT_DISMISSED_BY, alert.getDismissedBy());
            item.addProperty(Alert.ALERT_DISMISSED_TIME, alert.getDismissedTime());
        }

        try {
            persistentStore.add(CORE_NAME, item);
        } catch (PersistenceException e) {
            LOGGER.error("Failed to persist alert.");
        }
    }

    private Alert getAlertFromEvent(Event event) {
        Alert alert = new Alert();
        for (String name : event.getPropertyNames()) {
            alert.put(name, event.getProperty(name));
        }
        return alert;
    }

    private Alert getAlertBySource(String source) {
        return getSingleAlertFromStore(String.format("%s = '%s' AND %s = '%s' AND %s = '%s'",
                Alert.SYSYTEM_NOTICE_SOURCE_KEY,
                source,
                Alert.ALERT_STATUS,
                Alert.ALERT_ACTIVE_STATUS,
                Alert.SYSYTEM_NOTICE_HOST_NAME_KEY,
                hostName));
    }

    private Alert getAlertById(String id) {
        return getSingleAlertFromStore(String.format("id = '%s'", id));
    }

    private Alert getSingleAlertFromStore(String cql) {
        List<Alert> alerts = getAlertFromStore(cql);
        if (!alerts.isEmpty()) {
            return alerts.get(0);
        }
        return null;
    }

    private List<Alert> getAlertFromStore(String cql) {
        List<Alert> alerts = new ArrayList<>();
        try {
            List<Map<String, Object>> results = persistentStore.get(CORE_NAME, cql);
            if (!results.isEmpty()) {
                for (Map<String, Object> item : results) {
                    alerts.add(new Alert(PersistentItem.stripSuffixes(item)));
                }
            }
        } catch (PersistenceException pe) {
            LOGGER.error("Error retrieving system alert.", pe);
        }
        return alerts;
    }

    private void firePeriodicEvent() {
        List<Alert> alerts = getAlertFromStore(String.format("%s = '%s'",
                Alert.ALERT_STATUS,
                Alert.ALERT_ACTIVE_STATUS));
        if (alerts.isEmpty()) {
            return;
        }
        eventAdmin.postEvent(new Event(PeriodicAlert.PERIODIC_TOPIC, new PeriodicAlert(alerts)));
    }

    private void dismissAlert(Event dismissEvent) {
        String id = (String) dismissEvent.getProperty(Alert.SYSYTEM_NOTICE_ID_KEY);
        if (id != null) {
            Alert alert = getAlertById(id);
            if (alert == null) {
                LOGGER.debug("Could not find alert {} for dismissal.", id);
                return;
            }

            String dismissedBy = (String) dismissEvent.getProperty(Alert.ALERT_DISMISSED_BY);
            if (dismissedBy == null) {
                LOGGER.debug("Could not dismiss alert {} because the {} property was not provided.",
                        id,
                        Alert.ALERT_DISMISSED_BY);
                return;
            }

            alert.setStatus(Alert.ALERT_DISMISSED_STATUS);
            alert.setDismissedTime(Date.from(Instant.now()));
            alert.setDismissedBy(dismissedBy);
            addAlertToStore(alert);
        }
    }

    public long getPeriod() {
        return period;
    }

    public void setPeriod(long period) {
        this.period = period;
        this.scheduledFuture.cancel(false);
        scheduledFuture = executorService.scheduleAtFixedRate(this::firePeriodicEvent,
                period,
                period,
                TimeUnit.MINUTES);
    }
}
