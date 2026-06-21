import { useTranslation } from "react-i18next";

export function FormbricksBranding() {
  const { t } = useTranslation();
  return (
    <span className="flex justify-center">
      <a href="https://arthize.com?utm_source=survey_branding" target="_blank" tabIndex={-1} rel="noopener">
        <p className="text-signature text-xs">
          {t("common.powered_by")}{" "}
          <b>
            <span className="text-branding-text hover:text-signature">Artha Forms</span>
          </b>
        </p>
      </a>
    </span>
  );
}
