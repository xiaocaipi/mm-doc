#!/bin/bash

# Git 提交脚本
# 用法: ./commit.sh "提交信息"

# 检查是否提供了提交信息
if [ -z "$1" ]; then
    echo "错误: 请提供提交信息"
    echo "用法: ./commit.sh \"你的提交信息\""
    exit 1
fi

COMMIT_MSG="$1"

echo "=========================================="
echo "开始执行 Git 提交流程"
echo "提交信息: $COMMIT_MSG"
echo "=========================================="
echo ""

# 添加所有更改
echo "[1/4] 添加文件到暂存区..."
git add .
if [ $? -ne 0 ]; then
    echo "错误: git add 失败"
    exit 1
fi
echo "✓ 文件已添加"
echo ""

# 提交更改
echo "[2/4] 提交更改..."
git commit -m "$COMMIT_MSG"
if [ $? -ne 0 ]; then
    echo "错误: git commit 失败"
    exit 1
fi
echo "✓ 提交成功"
echo ""

# 推送到远程仓库
echo "[3/4] 推送到远程仓库 origin main..."
git push origin main
if [ $? -ne 0 ]; then
    echo "错误: git push 失败"
    exit 1
fi
echo "✓ 推送成功"
echo ""

# 显示提交状态
echo "[4/4] 提交状态:"
echo "=========================================="
git log -1 --oneline
echo "=========================================="
echo ""
echo "✓ Git 提交流程完成!"
