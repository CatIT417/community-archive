DROP MATERIALIZED VIEW IF EXISTS public.account_activity_summary;

CREATE MATERIALIZED VIEW public.account_activity_summary AS
SELECT
  a.account_id,
  a.username,
  a.num_tweets,
  a.num_followers,
  (SELECT COUNT(*) FROM public.likes l WHERE l.account_id = a.account_id) AS total_likes,
  (SELECT COUNT(*) FROM public.user_mentions um JOIN public.tweets t ON um.tweet_id = t.tweet_id WHERE t.account_id = a.account_id) AS total_mentions,
  (SELECT json_agg(row_to_json(m)) FROM (
    SELECT * FROM get_account_most_mentioned_accounts(a.username, 20)
  ) m) AS mentioned_accounts,
  (SELECT json_agg(row_to_json(rt)) FROM (
    SELECT * FROM get_account_top_retweet_count_tweets(a.username, 100)
  ) rt) AS most_retweeted_tweets,
  (SELECT json_agg(row_to_json(f)) FROM (
    SELECT * FROM get_account_top_favorite_count_tweets(a.username, 100)
  ) f) AS most_favorited_tweets,
  CURRENT_TIMESTAMP AS last_updated
FROM public.account a;

CREATE UNIQUE INDEX idx_account_activity_summary_account_id
ON public.account_activity_summary (account_id);
