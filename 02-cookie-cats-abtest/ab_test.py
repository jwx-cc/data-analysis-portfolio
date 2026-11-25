"""
Cookie Cats A/B 测试完整分析
数据：cookie_cats.csv（Kaggle - Mobile Games AB Testing）
运行：python ab_test.py
      python ab_test.py --data path/to/cookie_cats.csv
"""
import argparse
import pandas as pd
import numpy as np
from scipy import stats
import statsmodels.stats.proportion
import warnings
warnings.filterwarnings('ignore')

pd.set_option('display.width', 200)
pd.set_option('display.max_columns', 20)

SEP = "=" * 70

parser = argparse.ArgumentParser(description="Cookie Cats A/B 测试分析")
parser.add_argument("--data", default="cookie_cats.csv",
                    help="数据文件路径，默认为当前目录下的 cookie_cats.csv")
args = parser.parse_args()

# ============================================================
# 1. 数据加载与概览
# ============================================================
print(SEP)
print("1. 数据概览")
print(SEP)

df = pd.read_csv(args.data)
print(f"总行数: {len(df):,}")
print(f"字段: {list(df.columns)}")
print(f"\n分组分布:")
print(df['version'].value_counts())
print(f"\n分组占比:")
print(df['version'].value_counts(normalize=True).round(4))
print(f"\n缺失值:")
print(df.isnull().sum())
print(f"\nsum_gamerounds 描述统计:")
print(df['sum_gamerounds'].describe())

# ============================================================
# 2. 数据质量检查
# ============================================================
print("\n" + SEP)
print("2. 数据质量检查")
print(SEP)

# 2.1 用户 ID 唯一性
dup = df['userid'].duplicated().sum()
print(f"重复 userid 数: {dup}  ({'通过' if dup == 0 else '异常！'})")

# 2.2 分组均衡性（样本比例检验）
n_a = (df['version'] == 'gate_30').sum()
n_b = (df['version'] == 'gate_40').sum()
print(f"\n对照组 gate_30: {n_a:,}")
print(f"实验组 gate_40: {n_b:,}")
print(f"样本比例: {n_a/len(df):.4f} : {n_b/len(df):.4f}")
# 卡方拟合优度检验：实际分组是否偏离 50:50
chi2_srm, p_srm = stats.chisquare([n_a, n_b])
print(f"样本比例偏差检验 (SRM) p 值: {p_srm:.4f}  "
      f"({'通过，分组均衡' if p_srm > 0.05 else '警告：样本比例失衡'})")

# 2.3 异常值检查
print(f"\nsum_gamerounds 最大值: {df['sum_gamerounds'].max():,}")
print(f"分位数:")
for q in [0.5, 0.9, 0.99, 0.999, 1.0]:
    print(f"  {q*100:5.1f}%: {df['sum_gamerounds'].quantile(q):,.0f}")

outlier = df[df['sum_gamerounds'] > 2000]
print(f"\n超过 2000 局的用户: {len(outlier)} 人")
print(outlier[['userid', 'version', 'sum_gamerounds']].head(10).to_string(index=False))

# ============================================================
# 3. 主指标：留存率
# ============================================================
print("\n" + SEP)
print("3. 主指标分析：留存率")
print(SEP)

for metric in ['retention_1', 'retention_7']:
    print(f"\n--- {metric} ---")
    tab = pd.crosstab(df['version'], df[metric])
    print(tab)

    # 各组的留存率
    rates = df.groupby('version')[metric].agg(['sum', 'count', 'mean'])
    rates.columns = ['留存人数', '总人数', '留存率']
    rates['留存率'] = rates['留存率'].round(4)
    print(f"\n{rates.to_string()}")

    r30 = rates.loc['gate_30', '留存率']
    r40 = rates.loc['gate_40', '留存率']
    abs_diff = r30 - r40
    rel_diff = abs_diff / r40

    print(f"\n绝对差异 (gate_30 - gate_40): {abs_diff*100:+.3f} pp")
    print(f"相对差异: {rel_diff*100:+.2f}%")

    # 卡方检验
    ct = pd.crosstab(df['version'], df[metric])
    chi2, p_chi, dof, expected = stats.chi2_contingency(ct)
    print(f"\n卡方检验: chi2={chi2:.4f}, dof={dof}, p={p_chi:.6f}")

    # 两比例 z 检验（与卡方等价，但能算 CI）
    count = np.array([rates.loc['gate_30', '留存人数'], rates.loc['gate_40', '留存人数']])
    nobs = np.array([rates.loc['gate_30', '总人数'], rates.loc['gate_40', '总人数']])
    z_stat, p_z = statsmodels.stats.proportion.proportions_ztest(count, nobs)
    print(f"两比例 z 检验: z={z_stat:.4f}, p={p_z:.6f}")

    # 95% 置信区间（两比例差的 CI）
    ci_low, ci_high = statsmodels.stats.proportion.proportion_confint(count, nobs, alpha=0.05, method='normal')
    # 差值 CI
    se_diff = np.sqrt(r30*(1-r30)/n_a + r40*(1-r40)/n_b)
    z_crit = stats.norm.ppf(0.975)
    diff_ci = (abs_diff - z_crit*se_diff, abs_diff + z_crit*se_diff)
    print(f"\n留存率 95% CI:")
    print(f"  gate_30: [{ci_low[0]*100:.3f}%, {ci_high[0]*100:.3f}%]")
    print(f"  gate_40: [{ci_low[1]*100:.3f}%, {ci_high[1]*100:.3f}%]")
    print(f"差异 95% CI: [{diff_ci[0]*100:+.3f} pp, {diff_ci[1]*100:+.3f} pp]")

    # 效应量 Cohen's h
    h = 2*np.arcsin(np.sqrt(r30)) - 2*np.arcsin(np.sqrt(r40))
    print(f"效应量 Cohen's h: {h:+.4f}  (|h|<0.2 为小效应)")

    # 优势比 OR
    a, b = tab.loc['gate_30', True], tab.loc['gate_30', False]
    c, d = tab.loc['gate_40', True], tab.loc['gate_40', False]
    odds_ratio = (a*d) / (b*c)
    print(f"优势比 OR: {odds_ratio:.4f}")

    # 结论：先判显著，再判效应（顺序不能反）
    print(f"\n>>> 统计显著性: {'显著 (p<0.05)' if p_chi < 0.05 else '不显著 (p>=0.05)'}")
    if p_chi < 0.05:
        print(f">>> 效应解读: 差异显著，绝对效应 {abs(abs_diff)*100:.2f}pp，"
              f"{'具备业务价值' if abs(abs_diff) >= 0.005 else '但效应过小，业务价值有限'}")
    else:
        print(f">>> 效应解读: 差异不显著，数据不足以支持两组存在差异（不做业务解读）")

# ============================================================
# 4. 次指标：游戏局数
# ============================================================
print("\n" + SEP)
print("4. 次指标：14 天游戏局数")
print(SEP)

g30 = df[df['version'] == 'gate_30']['sum_gamerounds']
g40 = df[df['version'] == 'gate_40']['sum_gamerounds']

print(f"gate_30: 均值={g30.mean():.2f}, 中位数={g30.median():.0f}, 标准差={g30.std():.2f}")
print(f"gate_40: 均值={g40.mean():.2f}, 中位数={g40.median():.0f}, 标准差={g40.std():.2f}")

# 正态性检验（数据严重右偏，用非参数检验）
print(f"\n偏度: gate_30={g30.skew():.2f}, gate_40={g40.skew():.2f}  (严重右偏，t 检验不适用)")

# Mann-Whitney U 检验
u_stat, p_mw = stats.mannwhitneyu(g30, g40, alternative='two-sided')
print(f"Mann-Whitney U 检验: U={u_stat:.0f}, p={p_mw:.6f}")
print(f">>> {'显著' if p_mw < 0.05 else '不显著'}")

# 去掉极端值后重跑（敏感性分析）
print(f"\n[敏感性分析] 剔除 sum_gamerounds > 2000 的 {len(outlier)} 个极端用户后:")
df_clean = df[df['sum_gamerounds'] <= 2000]
g30c = df_clean[df_clean['version'] == 'gate_30']['sum_gamerounds']
g40c = df_clean[df_clean['version'] == 'gate_40']['sum_gamerounds']
u2, p2 = stats.mannwhitneyu(g30c, g40c, alternative='two-sided')
print(f"  gate_30 均值={g30c.mean():.2f}, gate_40 均值={g40c.mean():.2f}")
print(f"  Mann-Whitney p={p2:.6f}  ({'结论稳健' if (p2<0.05) == (p_mw<0.05) else '结论翻转！需谨慎'})")

# ============================================================
# 5. 样本量回溯（power analysis）
# ============================================================
print("\n" + SEP)
print("5. 样本量回溯：检测这个效应需要多少人")
print(SEP)

from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize

# retention_7 的效应
r30_7 = df[df['version']=='gate_30']['retention_7'].mean()
r40_7 = df[df['version']=='gate_40']['retention_7'].mean()
effect = proportion_effectsize(r30_7, r40_7)
power_analysis = NormalIndPower()
required_n = power_analysis.solve_power(
    effect_size=effect, alpha=0.05, power=0.8, alternative='two-sided'
)
print(f"retention_7 效应量 Cohen's h = {effect:.4f}")
print(f"每组所需样本量 (α=0.05, power=0.8): {required_n:,.0f}")
print(f"实际样本量: gate_30={n_a:,}, gate_40={n_b:,}")
print(f">>> {'样本量充足' if min(n_a, n_b) >= required_n else '样本量不足'}")

# 当前样本能检测的最小效应
mde = power_analysis.solve_power(
    effect_size=None, nobs1=min(n_a, n_b), alpha=0.05, power=0.8, alternative='two-sided'
)
print(f">>> 当前样本量能检测到的最小效应 Cohen's h = {mde:.4f}")

# ============================================================
# 6. 多重比较说明
# ============================================================
print("\n" + SEP)
print("6. 多重比较校正")
print(SEP)

p_values = []
for metric in ['retention_1', 'retention_7']:
    ct = pd.crosstab(df['version'], df[metric])
    _, p, _, _ = stats.chi2_contingency(ct)
    p_values.append(p)

print(f"未校正 p 值: retention_1={p_values[0]:.6f}, retention_7={p_values[1]:.6f}")

# Bonferroni 校正
alpha_bonf = 0.05 / len(p_values)
print(f"Bonferroni 校正后 α = {alpha_bonf:.4f}")
for metric, p in zip(['retention_1', 'retention_7'], p_values):
    sig_raw = "显著" if p < 0.05 else "不显著"
    sig_bonf = "显著" if p < alpha_bonf else "不显著"
    print(f"  {metric}: 未校正={sig_raw}, 校正后={sig_bonf}")

# ============================================================
# 7. 汇总结论
# ============================================================
print("\n" + SEP)
print("7. 分析结论")
print(SEP)

print("""
【实验设计】
  对照组 gate_30：玩家在第 30 关遇到强制门槛
  实验组 gate_40：门槛后移到第 40 关
  假设：减少早期打断 → 提升留存

【主指标结论】
  retention_1：两组差异不显著，gate 位置对次日留存无影响
  retention_7：gate_30 显著优于 gate_40，差异约 0.8pp

【次指标结论】
  游戏局数：分布严重右偏，Mann-Whitney 检验显示两组无显著差异

【业务建议】
  维持 gate 在第 30 关。后移到 40 关不仅没有提升留存，反而在 7 日留存上
  造成显著下降——早期门槛虽然打断体验，但起到了筛选高意愿用户、
  建立游戏节奏的作用。移除门槛并不能换来留存。

【方法局限】
  1. 未提供实验前样本量规划，属事后回溯
  2. 仅两个留存指标，缺少付费、ARPU 等商业化指标
  3. 未做用户分层（新老用户、地区、设备），可能存在辛普森悖论
  4. 14 天观察窗偏短，无法评估长期留存
""")

print(SEP)
print("分析完成")
print(SEP)
