package com.github.dominikschlosser;

import de.arbeitsagentur.opdt.keycloak.cassandra.CassandraDatastoreProvider;
import org.keycloak.models.*;

public class CloudNativeDatastoreProvider extends CassandraDatastoreProvider {
    private KeycloakSession session;

    public CloudNativeDatastoreProvider(KeycloakSession session) {
        super(session);
        this.session = session;
    }

    @Override
    public ClientProvider clients() {
        return session.getProvider(ClientProvider.class, "file");
    }

    @Override
    public ClientScopeProvider clientScopes() {
        return session.getProvider(ClientScopeProvider.class, "file");
    }

    @Override
    public GroupProvider groups() {
        return session.getProvider(GroupProvider.class, "file");
    }

    @Override
    public RealmProvider realms() {
        return session.getProvider(RealmProvider.class, "file");
    }

    @Override
    public RoleProvider roles() {
        return session.getProvider(RoleProvider.class, "file");
    }
}
