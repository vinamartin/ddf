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
package org.codice.ddf.system.alerts;

import java.time.Instant;
import java.util.Date;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

public class Alert extends SystemNotice {

    public static final String ALERT_BASE_TOPIC = "decanter/alert/";

    public static final String ALERT_DISMISS_TOPIC = "ddf/alert/dismiss";

    public static final String ALERT_EVENT_TYPE = "system-alert";

    public static final String ALERT_LAST_UPDATED = "last-updated";

    public static final String ALERT_COUNT = "count";

    public static final String ALERT_STATUS = "status";

    public static final String ALERT_DISMISSED_TIME = "dismissed-time";

    public static final String ALERT_DISMISSED_BY = "dismissed-by";

    public static final String ALERT_DISMISSED_STATUS = "dismissed";

    public static final String ALERT_ACTIVE_STATUS = "active";

    public Alert() {
        super();
        put(EVENT_TYPE_KEY, ALERT_EVENT_TYPE);
        setCount(1L);
        setLastUpdated(Date.from(Instant.now()));
        setStatus(ALERT_ACTIVE_STATUS);
    }

    public Alert(String source, int priority, String title, Set<String> details) {
        this();
        setSource(source);
        setPriority(priority);
        setTitle(title);
        setDetails(details == null ? new HashSet<>() : details);

    }

    public Alert(Map<String, Object> map) {
        this.putAll(map);
    }

    public Date getLastUpdated() {
        return (Date) this.get(ALERT_LAST_UPDATED);
    }

    public Long getCount() {
        return (Long) this.get(ALERT_COUNT);
    }

    public String getStatus() {
        return (String) this.get(ALERT_STATUS);
    }

    public Date getDismissedTime() {
        return (Date) this.get(ALERT_DISMISSED_TIME);
    }

    public String getDismissedBy() {
        return (String) this.get(ALERT_DISMISSED_BY);
    }

    public void setStatus(String status) {
        this.put(ALERT_STATUS, status);
    }

    public void setLastUpdated(Date time) {
        this.put(ALERT_LAST_UPDATED, time);
    }

    public void setCount(Long count) {
        this.put(ALERT_COUNT, count);
    }

    public void setDismissedTime(Date time) {
        this.put(ALERT_DISMISSED_TIME, time);
    }

    public void setDismissedBy(String dismissedBy) {
        this.put(ALERT_DISMISSED_BY, dismissedBy);
    }

}