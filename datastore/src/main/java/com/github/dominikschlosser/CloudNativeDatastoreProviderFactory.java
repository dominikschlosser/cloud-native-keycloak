package com.github.dominikschlosser;

import com.google.auto.service.AutoService;
import de.arbeitsagentur.opdt.keycloak.cassandra.CassandraDatastoreProviderFactory;
import de.arbeitsagentur.opdt.keycloak.common.ProviderHelpers;
import org.keycloak.models.KeycloakSession;
import org.keycloak.storage.DatastoreProvider;
import org.keycloak.storage.DatastoreProviderFactory;

@AutoService(DatastoreProviderFactory.class)
public class CloudNativeDatastoreProviderFactory extends CassandraDatastoreProviderFactory {
    @Override
    public DatastoreProvider create(KeycloakSession session) {
        return ProviderHelpers.createProviderCached(session, CloudNativeDatastoreProvider.class, () -> new CloudNativeDatastoreProvider(session));
    }

    @Override
    public int order() {
        return super.order() + 1;
    }
}
