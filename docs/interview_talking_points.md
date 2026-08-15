# Interview talking points

Answers are concise and limited to what the completed analysis actually did.

## 1. What was the scientific question?

Among children and adolescents with AML, which baseline patient and disease characteristics are associated with overall survival? This is an observational prognostic association question. I did not estimate causal effects of treatment or of intervening on a mutation.

## 2. Why was data cleaning difficult?

The GDC Cases API had survival and demographics but not the AML-specific baseline variables I needed. Those lived in seven overlapping open supplement workbooks. Vital status agreed well across sources, but some supplement OS-time fields were discordant, so GDC became the endpoint source. The extract also contained experimental and cell-line identifiers that are not patients.

## 3. Why did you freeze the cohort before modeling?

If eligibility depends on which predictors are complete or which associations look strong, the study population becomes a result of the analysis. I locked identity rules, the age cutoff, and the Alive/Dead endpoint first. Predictor completeness was not an inclusion criterion. That is ordinary collaborative-biostatistics practice.

## 4. Why Cox regression?

The endpoint is right-censored overall survival. Cox models give adjusted hazard ratios that investigators can read directly. I used the Efron tie method, no interactions, and no stepwise selection. The project was not trying to build a prediction score.

## 5. Why multiple imputation instead of dropping missing cases?

Complete-case analysis would have dropped 117 primary-model patients and 153 secondary-model patients after the cohort was already frozen. That changes both sample composition and precision. MICE was the prespecified primary method. Complete case remained a sensitivity analysis and was substantively similar.

## 6. Why use Nelson–Aalen information in MI?

If the imputation model ignores the outcome, associations with survival can be biased toward the null. I included the event indicator and a nonparametric Nelson–Aalen cumulative hazard as auxiliary variables. I did not impute survival time or the event itself.

## 7. How did you evaluate PH?

I used scaled Schoenfeld residuals (`cox.zph`), covariate-specific and global tests, residual correlation, and plots. A *p*-value below 0.05 was not automatically a major violation. Classification also considered whether the variable was a scientifically important predictor or a nuisance adjustment.

## 8. What did you do when WBC showed a minor PH departure?

The WBC Schoenfeld test was about *p* = 0.011 with a small residual correlation (|rho| ≈ 0.09). That did not meet the prespecified remediation threshold. I kept the primary log2-linear specification and interpret the WBC hazard ratio as an average relative hazard over follow-up. I did not add a time interaction after seeing the result.

## 9. Why separate risk group from molecular/cytogenetic predictors?

Protocol risk classification already uses cytogenetic and biomarker information. Putting risk group in the same principal model as FLT3/ITD and lesion flags would double-count overlapping biology. The two models answer related but different questions. That separation was a design decision, not the result of survival screening.

## 10. What would you do differently with investigator access?

I would confirm risk-group coding for the three unresolved `10`/`30` tokens, review whether any supplement OS-time discordance reflects a true clinical date versus a file artifact, and discuss whether a protocol-restricted sensitivity population is scientifically preferred. I would still not add variables or interactions because they looked significant.

## 11. What are the major limitations?

Observational public TARGET data; possible residual confounding; a MAR working assumption for MI; overlapping supplement sources; sparse categories such as monosomy 7; a small 10-year risk set; and no external validation. Concordance is descriptive, not predictive validation.

## 12. What did this project teach you about collaborative biostatistics?

Most of the important decisions happened before the first Cox fit: who is a patient, what time is time zero, which source wins when files disagree, and which model is primary. Writing those decisions down, and refusing to redesign the model after seeing hazard ratios, is the difference between an analysis and a fishing expedition.
