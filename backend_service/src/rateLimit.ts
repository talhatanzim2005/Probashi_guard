import { NextFunction, Request, Response } from 'express';

/**
 * Fixed-window, in-memory limiter, keyed by the verified user (or the IP when
 * there is none). One process only, which is right for a prototype: it exists
 * so a signed-in account cannot burn the Stripe API quota, not to stop a
 * distributed attack. Swap the Map for Redis if the service ever scales out.
 */
export function rateLimit(opts: { max: number; windowMs: number; name: string }) {
  const hits = new Map<string, { count: number; resetAt: number }>();

  return (req: Request, res: Response, next: NextFunction) => {
    const now = Date.now();
    const key = `${opts.name}:${res.locals.userId ?? req.ip ?? 'unknown'}`;
    let entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + opts.windowMs };
      hits.set(key, entry);
    }
    entry.count += 1;

    if (hits.size > 5000) {
      for (const [k, v] of hits) if (v.resetAt <= now) hits.delete(k);
    }

    if (entry.count > opts.max) {
      res.setHeader('Retry-After', Math.ceil((entry.resetAt - now) / 1000));
      return res.status(429).json({ error: 'Too many requests. Please slow down.' });
    }
    next();
  };
}
