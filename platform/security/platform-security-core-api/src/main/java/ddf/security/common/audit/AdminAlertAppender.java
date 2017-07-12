/**
 * Copyright (c) Codice Foundation
 * <p/>
 * This is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser
 * General Public License as published by the Free Software Foundation, either version 3 of the
 * License, or any later version.
 * <p/>
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
 * even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details. A copy of the GNU Lesser General Public License
 * is distributed along with this program and can be found at
 * <http://www.gnu.org/licenses/lgpl.html>.
 */
package ddf.security.common.audit;

import static org.apache.commons.lang.Validate.notNull;

import java.util.Collections;

import org.codice.ddf.system.alerts.NoticePriority;
import org.codice.ddf.system.alerts.SystemNotice;
import org.ops4j.pax.logging.spi.PaxAppender;
import org.ops4j.pax.logging.spi.PaxLoggingEvent;
import org.osgi.service.event.Event;
import org.osgi.service.event.EventAdmin;

public final class AdminAlertAppender implements PaxAppender {

    private final EventAdmin eventAdmin;

    public AdminAlertAppender(EventAdmin eventAdmin) {
        notNull(eventAdmin, "eventAdmin may not be null");
        this.eventAdmin = eventAdmin;
    }

    @Override
    public void doAppend(PaxLoggingEvent event) {
        SystemNotice notice = new SystemNotice(AdminAlertAppender.class.toString(),
                NoticePriority.CRITICAL.value(),
                "Failover Appender Failure",
                Collections.emptySet());
        eventAdmin.postEvent(new Event(SystemNotice.SYSTEM_NOTICE_BASE_TOPIC.concat("audit"), notice));
    }
}