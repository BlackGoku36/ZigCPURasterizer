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

# Loop traversal optimization
# 6.42
# 5.36

# 75.7
# 69.88

# 8.435
# 7.175

# obj's elements optimization

# dragon
# before: 64.965
# after (SOA): 57.57, 56.175, 57.1 (56.9 avg)
# after (AOS): 59.585
# after (AOSOA): 58.17

# spot
# before: 7.515
# after (SOA): 7.32
# after (AOSOA): 7.5