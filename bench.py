f = open("benchmark.txt", "r")

count = 0
sum = 0.0

for x in f:
    if(count == 200):
        break
    ms = x.split(" ")
    count += 1
    sum += float(ms[1])

f.close()

print(sum/count)

# 6.42
# 5.36

# 75.7
# 69.88

# 8.435
# 7.175