# Production Environment - Placeholder

This folder will contain the production environment infrastructure once dev is validated.

## Planned Structure

```
prod/
├── bootstrap/
│   ├── main.bicep          # Prod ACR deployment
│   └── main.bicepparam     # Prod ACR parameters
└── platform/
    ├── main.bicep          # Prod platform infrastructure
    └── main.bicepparam     # Prod platform parameters
```

## Differences from Dev

- **ACR Name**: `xshopaimodulesprod` (globally unique)
- **Zone Redundancy**: Enabled for high availability
- **Log Retention**: 90 days (compliance requirement)
- **SKUs**: Premium tier for critical resources
- **Backup**: Enabled for all stateful resources

## Deployment

Production deployment will be performed after dev environment is fully validated and tested.

**Status**: 🚧 Not yet implemented - waiting for dev validation
