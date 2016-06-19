//
// XMPPClient.swift
//
// TigaseSwift
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import Foundation

/**
 This is main class for use as XMPP client.
 
 `login()` and `disconnect()` methods as many other works asynchronously.
 
 Changes of state or informations about receiving XML packets are
 provided using events.
 
 To create basic client you need to:
 1. create instance of this class
 2. register used XmppModules in `modulesManager`
 3. use `connectionConfiguration` to set credentials for XMPP account.
 
 # Example usage
 ```
 let userJid = BareJID("user@domain.com");
 let password = "Pa$$w0rd";
 let client = XMPPClient();
 
 // register modules
 client.modulesManager.register(AuthModule());
 client.modulesManager.register(StreamFeaturesModule());
 client.modulesManager.register(SaslModule());
 client.modulesManager.register(ResourceBinderModule());
 client.modulesManager.register(SessionEstablishmentModule());
 client.modulesManager.register(DiscoveryModule());
 client.modulesManager.register(SoftwareVersionModule());
 client.modulesManager.register(PingModule());
 client.modulesManager.register(RosterModule());
 client.modulesManager.register(PresenceModule());
 client.modulesManager.register(MessageModule());
 
 // configure connection
 client.connectionConfiguration.setUserJID(userJid);
 client.connectionConfiguration.setUserPassword(password);
 
 // create and register event handler
 class EventBusHandler: EventHandler {
    init() {
    }
 
    func handleEvent(event: Event) {
        print("event bus handler got event = ", event);
        switch event {
        case is SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            print("successfully connected to server and authenticated!");
        case is RosterModule.ItemUpdatedEvent:
            print("roster item updated");
        case is PresenceModule.ContactPresenceChanged:
            print("received presence change event");
        case is MessageModule.ChatCreatedEvent:
            print("chat was created");
        case is MessageModule.MessageReceivedEvent:
            print("received message");
        default:
            // here will enter other events if this handler will be registered for any other events
            break;
        }
    }
 }

 let eventHandler = EventBusHandler();
 client.context.eventBus.register(eventHandler, events: SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, RosterModule.ItemUpdatedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE, MessageModule.MessageReceivedEvent.TYPE, MessageModule.ChatCreatedEvent.TYPE);
 
 // start XMPP connection to server
 client.login();
 
 // disconnect from server closing XMPP connection
 client.disconnect();
 ```
 
 */
public class XMPPClient: Logger, EventHandler {
    
    public let sessionObject:SessionObject;
    public let connectionConfiguration:ConnectionConfiguration!;
    public var socketConnector:SocketConnector? {
        willSet {
            sessionLogic?.unbind();
        }
    }
    public let modulesManager:XmppModulesManager!;
    public let eventBus:EventBus = EventBus();
    public let context:Context!;
    private var sessionLogic:XmppSessionLogic?;
    private let responseManager:ResponseManager;
    
    private var keepaliveTimer: Timer?;
    public var keepaliveTimeout: NSTimeInterval = (3 * 60) - 5;
    
    public var state:SocketConnector.State {
        return sessionLogic?.state ?? socketConnector?.state ?? .disconnected;
    }
    
    public override init() {
        sessionObject = SessionObject(eventBus:self.eventBus);
        connectionConfiguration = ConnectionConfiguration(self.sessionObject);
        modulesManager = XmppModulesManager();
        context = Context(sessionObject: self.sessionObject, eventBus:eventBus, modulesManager: modulesManager);
        responseManager = ResponseManager(context: context);
        super.init()
        eventBus.register(self, events: SocketConnector.DisconnectedEvent.TYPE);
    }
    
    deinit {
        eventBus.unregister(self, events: SocketConnector.DisconnectedEvent.TYPE);
    }
    
    /**
     Method initiates modules if needed and starts process of connecting to XMPP server.
     */
    public func login() -> Void {
        guard state == SocketConnector.State.disconnected else {
            log("XMPP in state:", state, " - not starting connection");
            return;
        }
        log("starting connection......");
        socketConnector = SocketConnector(context: context);
        context.writer = SocketPacketWriter(connector: socketConnector!, responseManager: responseManager);
        sessionLogic = SocketSessionLogic(connector: socketConnector!, modulesManager: modulesManager, responseManager: responseManager, context: context);
        sessionLogic!.bind();
        modulesManager.initIfRequired();
        
        keepaliveTimer?.cancel();
        if keepaliveTimeout > 0 {
            keepaliveTimer = Timer(delayInSeconds: keepaliveTimeout, repeats: true, callback: { Void->Void in self.keepalive() });
        } else {
            keepaliveTimer = nil;
        }
        
        socketConnector?.start()
    }

    /**
     Method closes connection to server.
     
     - parameter force: If passed XMPP connection will be closed by closing only TCP connection which makes it possible to use [XEP-0198: Stream Management - Resumption] if available and was enabled.
     
     [XEP-0198: Stream Management - Resumption]: http://xmpp.org/extensions/xep-0198.html#resumption
     */
    public func disconnect(force: Bool = false) -> Void {
        guard state == SocketConnector.State.connected || state == SocketConnector.State.connecting else {
            log("XMPP in state:", state, " - not stopping connection");
            return;
        }
        
        if force {
            socketConnector?.forceStop();
        } else {
            socketConnector?.stop();
        }
    }
    
    /**
     Sends whitespace to XMPP server to keep connection alive
     */
    public func keepalive() {
        guard state == .connected else {
            return;
        }
        socketConnector?.keepAlive();
    }
    
    /**
     Handles events fired by other classes used by this connection.
     */
    public func handleEvent(event: Event) {
        switch event {
        case let de as SocketConnector.DisconnectedEvent:
            keepaliveTimer?.cancel();
            keepaliveTimer = nil;
            if de.clean {
                context.sessionObject.clear();
            } else {
                context.sessionObject.clear(scopes: SessionObject.Scope.stream);
            }
            sessionLogic?.unbind();
            sessionLogic = nil;
            log("connection stopped......");
        default:
            log("received unhandled event:", event);
        }
    }
    
    /**
     Implementation of `PacketWriter` protocol passed to `Context` instance
     */
    private class SocketPacketWriter: PacketWriter {
        
        let connector:SocketConnector;
        let responseManager:ResponseManager;
        
        init(connector:SocketConnector, responseManager:ResponseManager) {
            self.connector = connector;
            self.responseManager = responseManager;
        }
        
        override func write(stanza: Stanza, timeout: NSTimeInterval = 30, callback: ((Stanza?) -> Void)?) {
            responseManager.registerResponseHandler(stanza, timeout: timeout, callback: callback);
            self.write(stanza);
        }
        
        override func write(stanza: Stanza, timeout: NSTimeInterval = 30, onSuccess: ((Stanza) -> Void)?, onError: ((Stanza,ErrorCondition?) -> Void)?, onTimeout: (() -> Void)?) {
            responseManager.registerResponseHandler(stanza, timeout: timeout, onSuccess: onSuccess, onError: onError, onTimeout: onTimeout);
            self.write(stanza);
        }

        override func write(stanza: Stanza, timeout: NSTimeInterval = 30, callback: AsyncCallback) {
            responseManager.registerResponseHandler(stanza, timeout: timeout, callback: callback);
            self.write(stanza);
        }

        override func write(stanza: Stanza) {
            self.connector.send(stanza);
        }
        
    }
}