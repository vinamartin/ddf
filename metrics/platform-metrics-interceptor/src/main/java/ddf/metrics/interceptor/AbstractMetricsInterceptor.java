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
package ddf.metrics.interceptor;

import org.apache.cxf.message.Exchange;
import org.apache.cxf.message.Message;
import org.apache.cxf.phase.AbstractPhaseInterceptor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.codahale.metrics.Histogram;
import com.codahale.metrics.JmxReporter;
import com.codahale.metrics.MetricRegistry;

/**
 * This class is extended by the METRICS interceptors used for capturing round trip message latency.
 *
 * @author willisod
 *
 */
public abstract class AbstractMetricsInterceptor extends AbstractPhaseInterceptor<Message> {

    private static final Logger LOGGER = LoggerFactory.getLogger(AbstractMetricsInterceptor.class);

    private static final String REGISTRY_NAME = "ddf.METRICS.services";

    private static final String HISTOGRAM_NAME = "Latency";

    private static final MetricRegistry METRICS = new MetricRegistry();

    private static final JmxReporter REPORTER = JmxReporter.forRegistry(METRICS)
            .inDomain(REGISTRY_NAME).build();

    final Histogram messageLatency;

    /**
     * Constructor to pass the phase to {@code AbstractPhaseInterceptor} and creates a new
     * histogram.
     *
     * @param phase
     */
    public AbstractMetricsInterceptor(String phase) {

        super(phase);

        messageLatency = METRICS.histogram(MetricRegistry.name(HISTOGRAM_NAME));

        REPORTER.start();
    }

    protected boolean isClient(Message msg) {
        return msg == null ? false : Boolean.TRUE.equals(msg.get(Message.REQUESTOR_ROLE));
    }

    protected void beginHandlingMessage(Exchange ex) {

        if (null == ex) {
            return;
        }

        LatencyTimeRecorder ltr = ex.get(LatencyTimeRecorder.class);

        if (null != ltr) {
            ltr.beginHandling();
        } else {
            ltr = new LatencyTimeRecorder();
            ex.put(LatencyTimeRecorder.class, ltr);
            ltr.beginHandling();
        }
    }

    protected void endHandlingMessage(Exchange ex) {

        if (null == ex) {
            return;
        }

        LatencyTimeRecorder ltr = ex.get(LatencyTimeRecorder.class);

        if (null != ltr) {
            ltr.endHandling();
            increaseCounter(ex, ltr);
        } else {
            LOGGER.info("can't get the MessageHandling Info");
        }
    }

    private void increaseCounter(Exchange ex, LatencyTimeRecorder ltr) {
        messageLatency.update(ltr.getLatencyTime());
    }

}
