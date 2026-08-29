/**
 * おはツイの「起動指示」だけを担当する Worker。
 *
 * GitHub Actions の on:schedule はキュー登録そのものが遅れることがあり、
 * 2026-08 に最大 +7時間59分 を実測した（全 run は success のまま、朝の
 * 投稿だけが昼過ぎにずれる）。定時性だけを Cloudflare の Cron Trigger に
 * 移し、実処理は onedrive-to-discord.yml にそのまま残してある。
 *
 * ここは workflow_dispatch を叩くだけ。失敗したら必ず Discord に鳴らす
 * ——PAT の期限切れで静かに死ぬのが、遅延と同じくらい怖いため。
 */

const OWNER = "BB999";
const REPO = "Metariea_ohapost";
const WORKFLOW = "onedrive-to-discord.yml";
const REF = "main";

export default {
  async scheduled(event, env) {
    await trigger(env);
  },
};

async function trigger(env) {
  // 値そのものは出さない。wrangler secret put は TTY なしだと空文字を
  // 登録して "Success" と言うので、型と長さだけ残して「無い」と「空」を
  // 区別できるようにしておく。
  console.log("GITHUB_TOKEN", typeof env.GITHUB_TOKEN, (env.GITHUB_TOKEN ?? "").length);

  const url = `https://api.github.com/repos/${OWNER}/${REPO}/actions/workflows/${WORKFLOW}/dispatches`;

  let res;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": `${REPO}-trigger`,
      },
      body: JSON.stringify({ ref: REF }),
    });
  } catch (e) {
    await notify(env, `⚠️ おはツイの起動指示に失敗（GitHubに到達できず）\n${e}`);
    throw e;
  }

  if (res.status === 204) {
    console.log("dispatched", WORKFLOW, REF);
    return;
  }

  const body = await res.text();
  await notify(
    env,
    `⚠️ おはツイの起動指示に失敗（HTTP ${res.status}）\n` +
      "GitHub Actions は動いていません。PATの期限切れ・権限不足を確認して。\n" +
      "```\n" + body.slice(0, 400) + "\n```",
  );
  throw new Error(`workflow_dispatch failed: ${res.status}`);
}

async function notify(env, content) {
  if (!env.DISCORD_WEBHOOK_URL) {
    console.error("DISCORD_WEBHOOK_URL が空。通知できない内容:", content);
    return;
  }
  try {
    await fetch(env.DISCORD_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content }),
    });
  } catch (e) {
    console.error("Discord通知に失敗", e);
  }
}
