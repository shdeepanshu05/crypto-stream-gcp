# ADR-0005: Use ECB rates from Frankfurter for USD→INR
Status: Accepted
Context: Phase 2 showed Frankfurter's default /v2/rates returns a Saturday rate (94.03) with no
source named, while /v2/providers/ecb/rates returns Friday's ECB rate (94.24). Sources differ by ~0.2%.
Decision: Use /v2/providers/ecb/rates. Trades on non-publishing days use the latest earlier rate (as-of join).
Alternatives considered: Default endpoint (fresher but unknown source, so poor lineage).
Consequences: One official, explainable rate per business day. INR values on weekends use Friday's rate.