//
// AuthModule.swift
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
import TigaseLogging

extension XmppModuleIdentifier {
    public static var auth: XmppModuleIdentifier<AuthModule> {
        return AuthModule.IDENTIFIER;
    }
}

/**
 Common authentication module provides generic support for authentication.
 Other authentication module (like ie. `SaslModule`) may require this
 module to work properly.
 */
open class AuthModule: XmppModule, ContextAware, EventHandler, Resetable {
    /// ID of module for lookup in `XmppModulesManager`
    public static let ID = "auth";
    public static let IDENTIFIER = XmppModuleIdentifier<AuthModule>();
    public static let CREDENTIALS_CALLBACK = "credentialsCallback";
    public static let LOGIN_USER_NAME_KEY = "LOGIN_USER_NAME";
    
    private let logger = Logger(subsystem: "TigaseSwift", category: "AuthModule");
        
    fileprivate var _context:Context!;
    open var context:Context! {
        get {
            return _context;
        }
        set {
            if newValue == nil {
                _context.eventBus.unregister(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthStartEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
            } else {
                newValue.eventBus.register(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthStartEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
            }
            _context = newValue;
        }
    }
    
    public let criteria = Criteria.empty();
    
    public let features = [String]();
    
    open private(set) var state: AuthorizationStatus = .notAuthorized;
    
    public init() {
        
    }
    
    open func process(stanza: Stanza) throws {
        
    }
    
    /**
     Starts authentication process using other module providing 
     mechanisms for authentication
     */
    open func login() {
        if let saslModule = _context.modulesManager.moduleOrNil(.sasl) {
            saslModule.login();
        }
    }
    
    /**
     Method handles events which needs to be processed by module
     for proper workflow.
     - parameter event: event to process
     */
    open func handle(event: Event) {
        switch event {
        case is SaslModule.SaslAuthSuccessEvent:
            let saslEvent = event as! SaslModule.SaslAuthSuccessEvent;
            self.state = .authorized;
            _context.eventBus.fire(AuthSuccessEvent(sessionObject: saslEvent.sessionObject));
        case is SaslModule.SaslAuthFailedEvent:
            let saslEvent = event as! SaslModule.SaslAuthFailedEvent;
            self.state = .notAuthorized;
            _context.eventBus.fire(AuthFailedEvent(sessionObject: saslEvent.sessionObject, error: saslEvent.error));
        case is SaslModule.SaslAuthStartEvent:
            let saslEvent = event as! SaslModule.SaslAuthStartEvent;
            self.state = .inProgress;
            _context.eventBus.fire(AuthStartEvent(sessionObject: saslEvent.sessionObject));
        default:
            logger.error("handing of unsupported event: \(event)");
        }
    }
    
    public func reset(scope: ResetableScope) {
        if scope == .session {
            state = .notAuthorized;
        } else {
            if state == .inProgress {
                state = .notAuthorized;
            }
        }
    }
    
    /// Event fired on authentication failure
    open class AuthFailedEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = AuthFailedEvent();
        
        public let type = "AuthFailedEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        /// Error returned by server during authentication
        public let error:SaslError!;
        
        init() {
            sessionObject = nil;
            error = nil;
        }
        
        public init(sessionObject: SessionObject, error: SaslError) {
            self.sessionObject = sessionObject;
            self.error = error;
        }
    }
    
    /// Event fired on start of authentication process
    open class AuthStartEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = AuthStartEvent();
        
        public let type = "AuthStartEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        
        init() {
            sessionObject = nil;
        }
        
        public init(sessionObject: SessionObject) {
            self.sessionObject = sessionObject;
        }
    }
    
    open class AuthFinishExpectedEvent: Event {
        
        public static let TYPE = AuthFinishExpectedEvent();
        
        public let type = "AuthFinishExpectedEvent";
        
        public let sessionObject: SessionObject!;
        
        init() {
            sessionObject = nil;
        }
        
        public init(sessionObject: SessionObject) {
            self.sessionObject = sessionObject;
        }
        
    }
    
    /// Event fired when after sucessful authentication
    open class AuthSuccessEvent: Event {
        /// Identifier of event which should be used during registration of `EventHandler`
        public static let TYPE = AuthSuccessEvent();
        
        public let type = "AuthSuccessEvent";
        /// Instance of `SessionObject` allows to tell from which connection event was fired
        public let sessionObject:SessionObject!;
        
        init() {
            sessionObject = nil;
        }
        
        public init(sessionObject: SessionObject) {
            self.sessionObject = sessionObject;
        }
    }
    
    public enum AuthorizationStatus {
        case notAuthorized
        case inProgress
        case authorized
    }
}
