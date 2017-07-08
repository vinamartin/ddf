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
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;

public class PeriodicAlert extends HashMap<String, Object> {
    public static final String PERIODIC_TOPIC = "ddf/periodic/notification/alert";

    public static final String ALERTS_KEY = "alerts";

    public static final String TIMESTAMP_KEY = "timestamp";

    public PeriodicAlert(List<Alert> alerts) {
        setTimestamp(Date.from(Instant.now()));
        setAlerts(alerts);
    }

    public List<Alert> getAlerts() {
        return (List<Alert>) this.getOrDefault(ALERTS_KEY, new ArrayList<Alert>());
    }

    public void setAlerts(List<Alert> alerts) {
        this.put(ALERTS_KEY, alerts);
    }

    public Date getTimestamp() {
        return (Date) this.getOrDefault(TIMESTAMP_KEY, Date.from(Instant.now()));
    }

    public void setTimestamp(Date date) {
        this.put(TIMESTAMP_KEY, date);
    }
}
