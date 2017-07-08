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

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

public class SystemNotice extends HashMap<String, Object> {

    public static final String SYSTEM_NOTICE_BASE_TOPIC = "decanter/collect/";

    public static final String SYSTEM_NOTICE_EVENT_TYPE = "system-notice";

    //common decanter fields
    public static final String EVENT_TYPE_KEY = "type";

    public static final String SYSYTEM_NOTICE_HOST_NAME_KEY = "hostName";

    public static final String SYSYTEM_NOTICE_HOST_ADDRESS_KEY = "hostAddress";

    public static final String SYSYTEM_NOTICE_TIME_KEY = "timestamp";

    //custom system notice fields
    public static final String SYSYTEM_NOTICE_ID_KEY = "id";

    public static final String SYSYTEM_NOTICE_SOURCE_KEY = "source";

    public static final String SYSYTEM_NOTICE_PRIORITY_KEY = "priority";

    public static final String SYSYTEM_NOTICE_TITLE_KEY = "title";

    public static final String SYSYTEM_NOTICE_DETAILS_KEY = "details";

    public SystemNotice() {
        put(EVENT_TYPE_KEY, SYSTEM_NOTICE_EVENT_TYPE);
        setTime(Date.from(Instant.now()));
        setId(UUID.randomUUID()
                .toString());
        setSource("Unknown");
        setPriority(NoticePriority.NORMAL.value());
        setTitle("");
        setDetails(new HashSet<>());

        try {
            setHostAddress(InetAddress.getLocalHost()
                    .getHostAddress());
            setHostName(InetAddress.getLocalHost()
                    .getHostName());
        } catch (UnknownHostException e) {
            // Should never happen
            throw new IllegalStateException(
                    "Cannot create system notice because the host name could not be retrieved. Reason: "
                            + e.getMessage());
        }
    }

    public SystemNotice(String source, int priority, String title, Set<String> details) {
        this();
        setSource(source);
        setPriority(priority);
        setTitle(title);
        setDetails(details == null ? new ArrayList<>() : details);

    }

    public String getId() {
        return (String) this.get(SYSYTEM_NOTICE_ID_KEY);
    }

    public String getSource() {
        return (String) this.get(SYSYTEM_NOTICE_SOURCE_KEY);
    }

    public String getHostName() {
        return (String) this.get(SYSYTEM_NOTICE_HOST_NAME_KEY);
    }

    public String getHostAddress() {
        return (String) this.get(SYSYTEM_NOTICE_HOST_ADDRESS_KEY);
    }

    public int getPriority() {
        return (int) this.get(SYSYTEM_NOTICE_PRIORITY_KEY);
    }

    public String getTitle() {
        return (String) this.get(SYSYTEM_NOTICE_TITLE_KEY);
    }

    public Set<String> getDetails() {
        return (Set<String>) this.get(SYSYTEM_NOTICE_DETAILS_KEY);
    }

    public Date getTime() {
        return (Date) this.get(SYSYTEM_NOTICE_TIME_KEY);
    }

    public void setId(String id) {
        this.put(SYSYTEM_NOTICE_ID_KEY, id);
    }

    public void setSource(String source) {
        this.put(SYSYTEM_NOTICE_SOURCE_KEY, source);
    }

    public void setHostName(String host) {
        this.put(SYSYTEM_NOTICE_HOST_NAME_KEY, host);
    }

    public void setHostAddress(String address) {
        this.put(SYSYTEM_NOTICE_HOST_ADDRESS_KEY, address);
    }

    public void setPriority(int priority) {
        this.put(SYSYTEM_NOTICE_PRIORITY_KEY, priority);
    }

    public void setTitle(String title) {
        this.put(SYSYTEM_NOTICE_TITLE_KEY, title);
    }

    public void setDetails(Collection<String> details) {
        this.put(SYSYTEM_NOTICE_DETAILS_KEY, details);
    }

    public void setTime(Date time) {
        this.put(SYSYTEM_NOTICE_TIME_KEY, time);
    }
}
