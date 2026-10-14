// Lambek as a GPS receiver of intents: each scorer is a satellite that measures how well a sentence fits an action.
// Fusion by the best linear unbiased estimator (BLUE, the weighted least squares of GNSS): w = S^-1 1 / (1' S^-1 1),
// corrected by the bias of each scorer (as DGPS corrects each satellite). Integrity as RAIM: a chi-square test on the
// residuals, solution separation (leave one scorer, then one family, out), a protection level against an alert limit
// set by the risk of the action. Probabilities calibrated by isotonic regression (PAV), then Chow's rule; conformal sets.
// A one-dimensional Kalman filter follows the bias of each scorer from the plans the user confirms.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;

public class LambekFusion
{
    public string[] Names = new string[0];
    public double[] Bias = new double[0];
    public double[][] Covariance = new double[0][];
    public double[] Weights = new double[0];
    public double Variance;
    public double ChiSquareLimit;
    public double[] CalibrationScore = new double[0];
    public double[] CalibrationProbability = new double[0];
    public double ConformalScore;
    public double ConformalAlpha = 0.05;
    public int Samples;
    public string[][] Families = new string[0][];
    // The actions the fusion was fitted on: only their choices can be judged by it
    public string[] Actions = new string[0];
    // Kalman: the bias correction learned from the user's own runs, and its variance
    public double[] Drift = new double[0];
    public double[] DriftVariance = new double[0];
    public static double Ridge = 1e-4;

    // Least squares with a covariance: the weights for a subset of scorers (the others weigh 0), all at least 0
    public double[] Blue(bool[] keep)
    {
        int n = Names.Length;
        bool[] active = (bool[])keep.Clone();
        for (int round = 0; round < n; round++)
        {
            int[] index = Enumerable.Range(0, n).Where(k => active[k]).ToArray();
            double[] w = new double[n];
            if (index.Length == 0) return w;
            double[,] sub = new double[index.Length, index.Length];
            for (int a = 0; a < index.Length; a++)
            {
                for (int b = 0; b < index.Length; b++) sub[a, b] = Covariance[index[a]][index[b]] + (a == b ? Ridge : 0);
            }
            double[,] inverse = Invert(sub);
            double[] row = new double[index.Length];
            double total = 0;
            for (int a = 0; a < index.Length; a++)
            {
                for (int b = 0; b < index.Length; b++) row[a] += inverse[a, b];
                total += row[a];
            }
            if (Math.Abs(total) < 1e-12) return w;
            int worst = -1;
            for (int a = 0; a < index.Length; a++)
            {
                w[index[a]] = row[a] / total;
                if (w[index[a]] < 0 && (worst < 0 || w[index[a]] < w[worst])) worst = index[a];
            }
            // A negative weight would trust a scorer upside down: leave it out and solve again
            if (worst < 0) return w;
            active[worst] = false;
        }
        return new double[n];
    }

    public double Spread(double[] w)
    {
        // w' S w: the variance of the fused score
        double v = 0;
        for (int a = 0; a < w.Length; a++)
        {
            for (int b = 0; b < w.Length; b++) v += w[a] * w[b] * Covariance[a][b];
        }
        return Math.Max(v, 0);
    }

    // Fused score, corrected by the published bias of each scorer; the user's own drift only when asked
    // (a decision must not depend on who used the engine before: same sentence, same packs, same verdict)
    public double Fuse(double[] z, double[] w)
    {
        return Fuse(z, w, false);
    }

    public double Fuse(double[] z, double[] w, bool personal)
    {
        double s = 0;
        for (int k = 0; k < w.Length; k++) s += w[k] * (z[k] - Bias[k] - (personal && Drift.Length > k ? Drift[k] : 0));
        return s;
    }

    // Effective number of independent signals (Kish): (sum w)^2 / (w' R w), R the correlation
    public double Independent(double[] w)
    {
        double sum = 0, spread = 0;
        for (int a = 0; a < w.Length; a++)
        {
            sum += w[a];
            for (int b = 0; b < w.Length; b++)
            {
                double scale = Math.Sqrt(Covariance[a][a] * Covariance[b][b]);
                double r = scale > 0 ? Covariance[a][b] / scale : (a == b ? 1 : 0);
                spread += w[a] * w[b] * r;
            }
        }
        return spread > 0 ? sum * sum / spread : 0;
    }

    // Residuals of the winner: r = z - b - S 1, and q = r' S^-1 r (a chi-square with n - 1 degrees of freedom without a fault)
    public double ChiSquare(double[] z, double fused)
    {
        int n = Names.Length;
        double[,] full = new double[n, n];
        for (int a = 0; a < n; a++) for (int b = 0; b < n; b++) full[a, b] = Covariance[a][b] + (a == b ? Ridge : 0);
        double[,] inverse = Invert(full);
        double[] r = new double[n];
        for (int k = 0; k < n; k++) r[k] = z[k] - Bias[k] - fused;
        double q = 0;
        for (int a = 0; a < n; a++) for (int b = 0; b < n; b++) q += r[a] * inverse[a, b] * r[b];
        return q;
    }

    // P(the action is the right one | fused score), a step function fitted by PAV
    public double Probability(double score)
    {
        if (CalibrationScore.Length == 0) return 0.5;
        int at = Array.BinarySearch(CalibrationScore, score);
        if (at < 0) at = ~at - 1;
        if (at < 0) return CalibrationProbability[0];
        return CalibrationProbability[Math.Min(at, CalibrationProbability.Length - 1)];
    }

    // Fit on labelled rows: for each request, each action scored (z), whether it is the right one
    public static LambekFusion Fit(string[] names, double[][] rows, bool[] right, int[] request, string[][] families, string[] actions)
    {
        LambekFusion fusion = new LambekFusion { Names = names, Families = families, Samples = rows.Length, Actions = actions };
        int n = names.Length;
        int m = rows.Length;

        // Errors e = z - y: their mean is the bias of each scorer, their covariance the geometry of the constellation
        fusion.Bias = new double[n];
        for (int k = 0; k < n; k++)
        {
            double sum = 0;
            for (int i = 0; i < m; i++) sum += rows[i][k] - (right[i] ? 1 : 0);
            fusion.Bias[k] = sum / Math.Max(m, 1);
        }
        fusion.Covariance = new double[n][];
        for (int a = 0; a < n; a++)
        {
            fusion.Covariance[a] = new double[n];
            for (int b = 0; b < n; b++)
            {
                double sum = 0;
                for (int i = 0; i < m; i++)
                {
                    double ea = rows[i][a] - (right[i] ? 1 : 0) - fusion.Bias[a];
                    double eb = rows[i][b] - (right[i] ? 1 : 0) - fusion.Bias[b];
                    sum += ea * eb;
                }
                fusion.Covariance[a][b] = sum / Math.Max(m - 1, 1);
            }
        }
        fusion.Drift = new double[n];
        fusion.DriftVariance = Enumerable.Range(0, n).Select(k => fusion.Covariance[k][k]).ToArray();
        fusion.Weights = fusion.Blue(Enumerable.Repeat(true, n).ToArray());
        fusion.Variance = fusion.Spread(fusion.Weights);

        // Calibration: isotonic regression of "right" on the fused score (pool adjacent violators), Laplace-smoothed blocks
        double[] fused = rows.Select(z => fusion.Fuse(z, fusion.Weights)).ToArray();
        int[] order = Enumerable.Range(0, m).OrderBy(i => fused[i]).ThenBy(i => i).ToArray();
        List<double> sums = new List<double>(), counts = new List<double>(), starts = new List<double>();
        foreach (int i in order)
        {
            sums.Add(right[i] ? 1 : 0);
            counts.Add(1);
            starts.Add(fused[i]);
            while (sums.Count > 1 && (sums[sums.Count - 2] + 1) / (counts[counts.Count - 2] + 2) >= (sums[sums.Count - 1] + 1) / (counts[counts.Count - 1] + 2))
            {
                int last = sums.Count - 1;
                sums[last - 1] += sums[last];
                counts[last - 1] += counts[last];
                sums.RemoveAt(last);
                counts.RemoveAt(last);
                starts.RemoveAt(last);
            }
        }
        fusion.CalibrationScore = starts.ToArray();
        fusion.CalibrationProbability = Enumerable.Range(0, sums.Count).Select(k => (sums[k] + 1) / (counts[k] + 2)).ToArray();

        // Chi-square limit: the 99th percentile of q on the right winners; conformal: the score that keeps 1 - alpha of the right actions
        List<double> qs = new List<double>();
        List<double> kept = new List<double>();
        foreach (int r in request.Distinct())
        {
            int[] mine = Enumerable.Range(0, m).Where(i => request[i] == r).ToArray();
            int winner = mine.OrderByDescending(i => fused[i]).ThenBy(i => i).First();
            if (right[winner]) qs.Add(fusion.ChiSquare(rows[winner], fused[winner]));
            foreach (int i in mine) if (right[i]) kept.Add(fused[i]);
        }
        qs.Sort();
        fusion.ChiSquareLimit = qs.Count > 0 ? qs[Math.Min(qs.Count - 1, (int)Math.Ceiling(0.99 * qs.Count) - 1)] : 13.28;
        kept.Sort();
        // Split conformal: the floor(alpha (n + 1))-th smallest score of the right actions
        int at = (int)Math.Floor(fusion.ConformalAlpha * (kept.Count + 1)) - 1;
        fusion.ConformalScore = kept.Count > 0 ? kept[Math.Max(0, Math.Min(kept.Count - 1, at))] : 0;
        return fusion;
    }

    // Weights for choosing one among several (how an answer is said): every point of the simplex with the given
    // number of steps, the one that puts the right row of most requests first; among those, the widest margin
    // between the right row and the best wrong one. The same points in the same order every time
    public static double[] Simplex(double[][] rows, bool[] right, int[] request, int steps)
    {
        int n = rows.Length > 0 ? rows[0].Length : 0;
        int[] requests = request.Distinct().OrderBy(r => r).ToArray();
        double[] best = new double[n];
        int bestHits = -1;
        double bestMargin = double.NegativeInfinity;
        int[] point = new int[n];
        Action<int, int> walk = null;
        walk = (k, left) =>
        {
            if (k == n - 1)
            {
                point[k] = left;
                double[] w = point.Select(p => p / (double)steps).ToArray();
                int hits = 0;
                double margin = 0;
                foreach (int r in requests)
                {
                    double good = double.NegativeInfinity, bad = double.NegativeInfinity;
                    for (int i = 0; i < rows.Length; i++)
                    {
                        if (request[i] != r) continue;
                        double s = 0;
                        for (int j = 0; j < n; j++) s += w[j] * rows[i][j];
                        if (right[i]) good = Math.Max(good, s); else bad = Math.Max(bad, s);
                    }
                    if (good > bad) hits++;
                    if (!double.IsInfinity(good) && !double.IsInfinity(bad)) margin += Math.Max(-1, Math.Min(1, good - bad));
                }
                if (hits > bestHits || (hits == bestHits && margin > bestMargin + 1e-12))
                {
                    bestHits = hits;
                    bestMargin = margin;
                    best = w;
                }
                return;
            }
            for (int v = 0; v <= left; v++)
            {
                point[k] = v;
                walk(k + 1, left - v);
            }
        };
        if (n > 0) walk(0, steps);
        return best;
    }

    // Kalman in one dimension: the bias of each scorer, seen on a plan the user confirmed (z for the action that ran is truth 1,
    // for the others truth 0). Process noise lets it follow a slow drift; the measurement noise is the scorer's variance
    public void Observe(double[][] rows, bool[] right, double process)
    {
        for (int k = 0; k < Names.Length; k++)
        {
            double noise = Math.Max(Covariance[k][k], 1e-6);
            for (int i = 0; i < rows.Length; i++)
            {
                double innovation = rows[i][k] - (right[i] ? 1 : 0) - Bias[k] - Drift[k];
                double p = DriftVariance[k] + process;
                double gain = p / (p + noise);
                Drift[k] += gain * innovation;
                DriftVariance[k] = (1 - gain) * p;
            }
        }
    }

    // Gauss-Jordan with partial pivoting, the same steps every time
    public static double[,] Invert(double[,] matrix)
    {
        int n = matrix.GetLength(0);
        double[,] a = (double[,])matrix.Clone();
        double[,] inverse = new double[n, n];
        for (int i = 0; i < n; i++) inverse[i, i] = 1;
        for (int column = 0; column < n; column++)
        {
            int pivot = column;
            for (int row = column + 1; row < n; row++) if (Math.Abs(a[row, column]) > Math.Abs(a[pivot, column])) pivot = row;
            if (Math.Abs(a[pivot, column]) < 1e-15) continue;
            if (pivot != column)
            {
                for (int k = 0; k < n; k++)
                {
                    double t = a[column, k]; a[column, k] = a[pivot, k]; a[pivot, k] = t;
                    t = inverse[column, k]; inverse[column, k] = inverse[pivot, k]; inverse[pivot, k] = t;
                }
            }
            double scale = a[column, column];
            for (int k = 0; k < n; k++) { a[column, k] /= scale; inverse[column, k] /= scale; }
            for (int row = 0; row < n; row++)
            {
                if (row == column) continue;
                double factor = a[row, column];
                if (factor == 0) continue;
                for (int k = 0; k < n; k++) { a[row, k] -= factor * a[column, k]; inverse[row, k] -= factor * inverse[column, k]; }
            }
        }
        return inverse;
    }

    // Saved as JSON, numbers written the same way in every culture
    public string Save()
    {
        Dictionary<string, object> data = new Dictionary<string, object>
        {
            { "Names", Names }, { "Bias", Bias }, { "Covariance", Covariance }, { "Weights", Weights }, { "Variance", Variance },
            { "ChiSquareLimit", ChiSquareLimit }, { "CalibrationScore", CalibrationScore }, { "CalibrationProbability", CalibrationProbability },
            { "ConformalScore", ConformalScore }, { "ConformalAlpha", ConformalAlpha }, { "Samples", Samples }, { "Families", Families },
            { "Actions", Actions }
        };
        return JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
    }

    public static LambekFusion Load(string json)
    {
        using (JsonDocument document = JsonDocument.Parse(json))
        {
            JsonElement root = document.RootElement;
            LambekFusion fusion = new LambekFusion
            {
                Names = root.GetProperty("Names").EnumerateArray().Select(e => e.GetString()).ToArray(),
                Bias = Numbers(root.GetProperty("Bias")),
                Covariance = root.GetProperty("Covariance").EnumerateArray().Select(Numbers).ToArray(),
                Weights = Numbers(root.GetProperty("Weights")),
                Variance = root.GetProperty("Variance").GetDouble(),
                ChiSquareLimit = root.GetProperty("ChiSquareLimit").GetDouble(),
                CalibrationScore = Numbers(root.GetProperty("CalibrationScore")),
                CalibrationProbability = Numbers(root.GetProperty("CalibrationProbability")),
                ConformalScore = root.GetProperty("ConformalScore").GetDouble(),
                ConformalAlpha = root.GetProperty("ConformalAlpha").GetDouble(),
                Samples = root.GetProperty("Samples").GetInt32(),
                Families = root.GetProperty("Families").EnumerateArray().Select(f => f.EnumerateArray().Select(e => e.GetString()).ToArray()).ToArray()
            };
            JsonElement actions;
            fusion.Actions = root.TryGetProperty("Actions", out actions) ? actions.EnumerateArray().Select(e => e.GetString()).ToArray() : new string[0];
            fusion.Drift = new double[fusion.Names.Length];
            fusion.DriftVariance = fusion.Covariance.Select((c, k) => c[k]).ToArray();
            return fusion;
        }
    }

    static double[] Numbers(JsonElement element)
    {
        return element.EnumerateArray().Select(e => e.GetDouble()).ToArray();
    }
}
