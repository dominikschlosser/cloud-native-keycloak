// Drives a real browser against the Keycloak admin console to prove a deployment works.
// It logs in as admin/admin, opens a realm's Clients page and asserts the client
// overview renders (a known client row appears).
//
// Env inputs:
//   BASE_URL       e.g. http://localhost:18080
//   REALM          realm whose Clients page is loaded (default master)
//   EXPECT_CLIENT  client id that must appear in the overview (default security-admin-console)
//   CHROME_PATH    path to a Chrome/Chromium binary
//   SHOT           optional screenshot output path
import puppeteer from "puppeteer-core";

const BASE_URL = process.env.BASE_URL || "http://localhost:18080";
const REALM = process.env.REALM || "master";
const EXPECT_CLIENT = process.env.EXPECT_CLIENT || "security-admin-console";
const CHROME_PATH =
  process.env.CHROME_PATH ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const SHOT = process.env.SHOT || "";
const USER = process.env.KC_ADMIN || "admin";
const PASS = process.env.KC_ADMIN_PASSWORD || "admin";

let PAGE = null;
const fail = async (msg) => {
  console.error(`verify: FAIL: ${msg}`);
  if (PAGE) {
    try {
      console.error(`verify: url=${PAGE.url()}`);
      const txt = await PAGE.evaluate(() =>
        (document.body ? document.body.innerText : "").slice(0, 600),
      );
      console.error(`verify: page text:\n${txt}`);
      if (SHOT) await PAGE.screenshot({ path: SHOT, fullPage: true });
    } catch {}
  }
  await browser.close();
  process.exit(1);
};

const browser = await puppeteer.launch({
  executablePath: CHROME_PATH,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

try {
  const page = await browser.newPage();
  PAGE = page;
  page.setDefaultTimeout(60000);
  page.setDefaultNavigationTimeout(60000);

  // Land on the admin console (redirects to the login form).
  await page.goto(`${BASE_URL}/admin/master/console/`, {
    waitUntil: "networkidle2",
  });

  await page
    .waitForSelector("#username", { visible: true })
    .catch(async () => fail("login form (#username) never appeared"));
  await page.type("#username", USER);
  await page.type("#password", PASS);
  await Promise.all([
    page.waitForNavigation({ waitUntil: "networkidle2" }),
    page.click("#kc-login"),
  ]);

  // A logged-in console leaves the login form behind. A failed login re-renders #username.
  if (await page.$("#username")) await fail("login rejected (still on login form)");
  console.log("verify: logged in to admin console");

  // Open the target realm's Clients overview and wait for the known client to render.
  // A hash-only change does not reload the SPA, so navigate then force a reload.
  await page.goto(`${BASE_URL}/admin/master/console/#/${REALM}/clients`, {
    waitUntil: "networkidle2",
  });
  await page.reload({ waitUntil: "networkidle2" });
  await page
    .waitForFunction(
      (client) => document.body && document.body.innerText.includes(client),
      { timeout: 60000 },
      EXPECT_CLIENT,
    )
    .catch(async () =>
      fail(`client "${EXPECT_CLIENT}" not found in ${REALM} Clients overview`),
    );

  if (SHOT) await page.screenshot({ path: SHOT, fullPage: true });
  console.log(
    `verify: OK: ${REALM} Clients overview rendered and lists "${EXPECT_CLIENT}"`,
  );
} finally {
  await browser.close();
}
