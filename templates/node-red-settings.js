module.exports = {
    flowFile: 'flows.json',
    flowFilePretty: true,

    https: {
        key: require("fs").readFileSync('@cert_dir@/key.pem'),
        cert: require("fs").readFileSync('@cert_dir@/cert.pem')
    },

    requireHttps: true,
    uiHost: "127.0.0.1",

    diagnostics: {
        enabled: true,
        ui: true,
    },

    runtimeState: {
        enabled: false,
        ui: false,
    },
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    exportGlobalContextKeys: false,
    externalModules: {},

    editorTheme: {
        palette: {},
        projects: {
            enabled: false,
            workflow: {
                mode: "manual"
            }
        },
        codeEditor: {
            lib: "monaco",
            options: {
            }
        }
    },

    functionExternalModules: true,
    functionGlobalContext: {},
    debugMaxLength: 1000,
    mqttReconnectTime: 15000,
    serialReconnectTime: 15000,

    dashboard: {
        middleware: (request, response, next) => {
            console.log('User name:', request.headers['x-vouch-user'])
            next()
        }
    },
}