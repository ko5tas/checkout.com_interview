#!/usr/bin/env python3
"""
Deterministic Terraform plan analyser with optional Gemini AI summary.

Reads a terraform plan text output and produces:
- Resource change counts (create/update/destroy)
- High-risk change flags (Key Vault, networking, APIM)
- Estimated cost impact
- AI-generated natural language summary (if GEMINI_API_KEY is set)

Usage: python3 scripts/analyze-plan.py plan-output.txt
"""

import json
import os
import re
import sys
import urllib.request


def parse_plan(plan_text: str) -> dict:
    """Parse terraform plan output into structured data."""
    creates = re.findall(r"#\s+(\S+)\s+will be created", plan_text)
    updates = re.findall(r"#\s+(\S+)\s+will be updated", plan_text)
    destroys = re.findall(r"#\s+(\S+)\s+will be destroyed", plan_text)
    replaces = re.findall(r"#\s+(\S+)\s+must be replaced", plan_text)
    no_changes = "No changes" in plan_text

    return {
        "creates": creates,
        "updates": updates,
        "destroys": destroys,
        "replaces": replaces,
        "no_changes": no_changes,
        "total_changes": len(creates) + len(updates) + len(destroys) + len(replaces),
    }


# Approximate monthly cost per Azure resource type
COST_MAP = {
    "azurerm_api_management": 50.0,
    "azurerm_private_endpoint": 7.50,
    "azurerm_linux_function_app": 0.0,
    "azurerm_service_plan": 0.0,
    "azurerm_storage_account": 1.0,
    "azurerm_key_vault": 1.0,
    "azurerm_log_analytics_workspace": 5.0,
    "azurerm_application_insights": 0.0,
}

# Resources that are high-risk to modify or destroy
HIGH_RISK_TYPES = {
    "azurerm_key_vault": "Data loss risk — secrets and certificates may be permanently deleted",
    "azurerm_virtual_network": "Connectivity risk — all VNet-integrated resources will lose connectivity",
    "azurerm_api_management": "Service disruption — APIM takes 30-45 min to provision",
    "azurerm_storage_account": "Data loss risk — function app state and logs",
    "azurerm_private_dns_zone": "DNS resolution risk — private endpoints may become unreachable",
}


def assess_risk(changes: dict) -> list:
    """Flag high-risk changes."""
    risks = []
    for resource in changes["destroys"] + changes["replaces"]:
        resource_type = resource.rsplit(".", 1)[0].split("[")[0]
        # Extract the terraform resource type from the address
        parts = resource.split(".")
        if len(parts) >= 2:
            rt = parts[0] if "module" not in parts[0] else parts[2] if len(parts) > 2 else parts[0]
            for risk_type, reason in HIGH_RISK_TYPES.items():
                if risk_type in resource:
                    risks.append({"resource": resource, "severity": "HIGH", "reason": reason})
    return risks


def estimate_cost_delta(changes: dict) -> float:
    """Estimate monthly cost impact of changes."""
    delta = 0.0
    for resource in changes["creates"]:
        for cost_type, cost in COST_MAP.items():
            if cost_type in resource:
                delta += cost
    for resource in changes["destroys"]:
        for cost_type, cost in COST_MAP.items():
            if cost_type in resource:
                delta -= cost
    return delta


def get_ai_summary(plan_text: str, analysis: str) -> str:
    """Get AI summary from Google Gemini (free tier)."""
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        return "*AI summary skipped — GEMINI_API_KEY not set*"

    prompt = f"""You are a senior SRE reviewing a Terraform plan for an Azure infrastructure deployment.
Summarise the following plan analysis in 3-5 bullet points, focusing on:
1. What is changing and why it matters
2. Any risks the team should be aware of
3. Cost implications

Plan analysis:
{analysis}

Plan excerpt (last 50 lines):
{chr(10).join(plan_text.split(chr(10))[-50:])}

Be concise and actionable. Use markdown formatting."""

    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"maxOutputTokens": 500, "temperature": 0.2},
    }).encode()

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        return f"*AI summary failed: {e}*"


def main():
    if len(sys.argv) < 2:
        print("Usage: analyze-plan.py <plan-output.txt>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        plan_text = f.read()

    changes = parse_plan(plan_text)

    # Build analysis report
    report = []
    report.append("## Plan Risk Analysis")
    report.append("")

    if changes["no_changes"]:
        report.append("No infrastructure changes detected.")
        print("\n".join(report))
        return

    report.append(f"| Metric | Count |")
    report.append(f"|--------|-------|")
    report.append(f"| Resources to create | {len(changes['creates'])} |")
    report.append(f"| Resources to update | {len(changes['updates'])} |")
    report.append(f"| Resources to destroy | {len(changes['destroys'])} |")
    report.append(f"| Resources to replace | {len(changes['replaces'])} |")
    report.append("")

    # Risk assessment
    risks = assess_risk(changes)
    if risks:
        report.append("### High-Risk Changes")
        report.append("")
        for risk in risks:
            report.append(f"- **{risk['severity']}**: `{risk['resource']}` — {risk['reason']}")
        report.append("")

    # Cost estimate
    cost_delta = estimate_cost_delta(changes)
    if cost_delta != 0:
        direction = "increase" if cost_delta > 0 else "decrease"
        report.append(f"### Estimated Cost Impact")
        report.append(f"Monthly cost {direction}: **${abs(cost_delta):.2f}/mo**")
        report.append("")

    analysis_text = "\n".join(report)

    # AI summary
    ai_summary = get_ai_summary(plan_text, analysis_text)
    report.append("### AI Summary")
    report.append(ai_summary)

    print("\n".join(report))


if __name__ == "__main__":
    main()
