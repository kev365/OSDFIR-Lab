# OSDFIR AI Integration Guide

This document describes the AI integration capabilities added to the OSDFIR Minikube lab environment.

## Overview

The OSDFIR lab now includes AI-powered analysis capabilities through:
- **Ollama**: Local AI model server
- **Gemma 3N 4B**: Specialized model for forensic analysis
- **OpenRelik Integration**: AI-assisted evidence processing

## AI Model Details

### Gemma 3N 4B Q4_K_M
- **Purpose**: Digital forensics and cybersecurity analysis
- **Size**: ~2.5GB download
- **Context Length**: 8,192 tokens
- **Quantization**: Q4_K_M (optimized for performance)
- **Capabilities**: 
  - Forensic artifact analysis
  - Timeline correlation
  - IOC identification
  - Pattern detection

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   OpenRelik     │───▶│     Ollama      │───▶│   Gemma 3N 4B   │
│  LLM Worker     │    │   AI Server     │    │   AI Model      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Deployment Process

1. **Automatic Model Download**: During deployment, Ollama automatically downloads the Gemma 3N model
2. **Service Integration**: OpenRelik workers are configured to communicate with Ollama
3. **Health Checks**: Built-in monitoring ensures AI services are operational

## Using AI Features

### Management Commands

```powershell
# Check AI status
.\manage-osdfir.ps1 ollama

# View AI model logs
kubectl logs -l app=ollama -n osdfir

# Test AI connectivity
kubectl exec -n osdfir <openrelik-pod> -- curl http://ollama.osdfir.svc.cluster.local:11434/api/tags
```

### OpenRelik AI Integration

The AI integration provides:

1. **Automated Analysis**: Evidence files are automatically analyzed for suspicious patterns
2. **Contextual Insights**: AI provides forensic context for discovered artifacts
3. **Correlation Detection**: Identifies relationships between different evidence sources
4. **Timeline Enhancement**: Adds AI-generated annotations to timeline events

### Example AI Queries

The AI can assist with:
- Malware behavior analysis
- Suspicious network activity detection
- File system anomaly identification
- Log pattern analysis
- IOC correlation

## Configuration

### Environment Variables

The following environment variables configure AI integration:

```yaml
OLLAMA_SERVER_URL: "http://ollama.osdfir.svc.cluster.local:11434"
OLLAMA_DEFAULT_MODEL: "ai/gemma3n:4B-Q4_K_M"
OPENRELIK_AI_ENABLED: "true"
OPENRELIK_AI_PROVIDER: "ollama"
```

### Model Configuration

```yaml
config:
  analyzers:
    llm:
      provider: "ollama"
      model: "ai/gemma3n:4B-Q4_K_M"
      max_input_tokens: 4096
      max_output_tokens: 1024
      temperature: 0.1
      system_prompt: |
        You are a digital forensics AI assistant...
```

## Resource Requirements

### Minimum Requirements
- **Memory**: 8GB total system RAM
- **CPU**: 4 cores
- **Storage**: 15GB additional for AI model
- **Network**: Internet access for model download

### Recommended Configuration
- **Memory**: 16GB+ system RAM
- **CPU**: 8+ cores
- **Storage**: 20GB+ for models and cache
- **GPU**: Optional but improves performance

## Troubleshooting

### Common Issues

1. **Model Download Timeout**
   ```bash
   # Check download progress
   kubectl logs ollama-<pod> -n osdfir -c model-puller
   
   # Manual model pull if needed
   kubectl exec -n osdfir ollama-<pod> -- ollama pull ai/gemma3n:4B-Q4_K_M
   ```

2. **OpenRelik Cannot Reach Ollama**
   ```bash
   # Test connectivity
   kubectl exec -n osdfir <openrelik-pod> -- nslookup ollama.osdfir.svc.cluster.local
   
   # Check service endpoints
   kubectl get endpoints ollama -n osdfir
   ```

3. **Out of Memory**
   ```bash
   # Check resource usage
   kubectl top pods -n osdfir
   
   # Scale down other services if needed
   kubectl scale deployment <deployment> --replicas=0 -n osdfir
   ```

### Performance Tuning

1. **Increase Ollama Memory**:
   ```yaml
   resources:
     limits:
       memory: "8Gi"  # Increase for better performance
   ```

2. **Adjust Worker Concurrency**:
   ```yaml
   command: "celery --app=src.app worker --concurrency=1"  # Reduce for memory constraints
   ```

3. **Model Cache Optimization**:
   ```yaml
   env:
     - name: OLLAMA_KEEP_ALIVE
       value: "24h"  # Keep model in memory longer
   ```

## Security Considerations

1. **Model Data**: AI models process case data locally within the cluster
2. **No External Calls**: All AI processing happens within your Minikube environment
3. **Data Isolation**: Each case maintains separate processing contexts
4. **Access Control**: AI features respect existing OSDFIR authentication

## Integration Examples

### Automated Log Analysis
```python
# Example: AI analyzes Windows event logs
result = openrelik_client.submit_task("llm_analyzer", {
    "file_path": "/evidence/Security.evtx",
    "prompt": "Identify suspicious authentication patterns"
})
```

### Timeline Enhancement
```python
# Example: AI enhances timeline events
enhanced_events = ai_service.analyze_timeline(
    events=timeline_data,
    context="Corporate network breach investigation"
)
```

## Limitations

1. **Local Processing**: All AI processing is local; no cloud AI services
2. **Model Size**: Limited by available system resources
3. **Accuracy**: AI suggestions should be verified by analysts
4. **Language**: Currently optimized for English forensic content

## Support and Updates

- **Model Updates**: Run `ollama pull ai/gemma3n:4B-Q4_K_M` to update the model
- **Configuration Changes**: Modify `helm/osdfir-lab-values.yaml` and redeploy
- **Monitoring**: Use `manage-osdfir.ps1 ollama` for health checks

For additional support, check the OpenRelik and Ollama documentation. 