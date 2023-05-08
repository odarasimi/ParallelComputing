# Tips for code optimization

# activate environment
# cd(@__DIR__)
# using Pkg
# Pkg.activate(".")

# import statements
using FiniteDiff, ForwardDiff, BenchmarkTools, StaticArrays, LinearAlgebra

#------------------------------------------------------------------------------------------
# check average time it takes to run this function when calling elements contiguously
# note that elements in a matrix are actually arranged in a linear array
#------------------------------------------------------------------------------------------
A = rand(100,100)
B = rand(100,100)
C = rand(100,100)

# the below function reads through the rows first
function inner_rows!(C,A,B)
    for i in 1:100, j in 1:100 # iterates through the rows(i) first, then the columns(j) after 
        C[i,j] = A[i,j] + B[i,j] # modify previously created array - C, so it does not reallocate memory
    end
end
@btime inner_rows!(C,A,B) # 10.300 μs (0 allocations: 0 bytes)

# the below function reads through the columns first
function inner_cols!(C,A,B)
    for j in 1:100, i in 1:100 # iterates through the columns(j) first, then the rows(i) after 
        C[i,j] = A[i,j] + B[i,j]
    end
end
@btime inner_cols!(C,A,B) # 6.440 μs (0 allocations: 0 bytes), this is faster because the convention used here = column major

#----------------------------------------------------------------------------------------------------------
# Stack: fixed piece of memory living close to your core with the location of everything known before hand( meaning that the size
# of variables are known at compile time). 
# Heap: dynamic allocation unit with a changing size, basically stores pointers to objects, 
# which are then brought all the way up to the cache when needed
#----------------------------------------------------------------------------------------------------------

function inner_alloc!(C,A,B)
    for j in 1:100, i in 1:100
        val = [A[i,j] + B[i,j]] # creates an array and hence a pointer to a piece of memory 100 x 100 times
        C[i,j] = val[1]
    end
end
@btime inner_alloc!(C,A,B) # 224.100 μs (10000 allocations: 625.00 KiB)

function inner_noalloc!(C,A,B)
    for j in 1:100, i in 1:100
        val = A[i,j] + B[i,j] # val is sent to the stack, no mem allocation
        C[i,j] = val[1]
    end
end
@btime inner_noalloc!(C,A,B) # 6.460 μs (0 allocations: 0 bytes)

# one way to send the array to the stack is to use StaticArrays...watch the size of your static array through
function static_inner_alloc!(C,A,B)
    for j in 1:100, i in 1:100
        val = @SVector [A[i,j] + B[i,j]] # the macro ensures knowledge of the array size at compile time, so it lives on the stack
        C[i,j] = val[1]
    end
end
@btime static_inner_alloc!(C,A,B) # 6.440 μs (0 allocations: 0 bytes)

# Mutation: you can also change the values of an existing array whenever you actually need to 
# write into arrays without performing an heap allocation. See the two functions below.

function inner_noalloc!(C,A,B)
    for j in 1:100, i in 1:100
        val = A[i,j] + B[i,j]
        C[i,j] = val[1]
    end
end
@btime inner_noalloc!(C,A,B) # 6.460 μs (0 allocations: 0 bytes)

function inner_alloc(A,B)
    C = similar(A)
    for j in 1:100, i in 1:100
        val = A[i,j] + B[i,j]
        C[i,j] = val[1]
    end
end
@btime inner_alloc(A,B) # 9.500 μs (2 allocations: 78.17 KiB)

#-------------------------------------------------------------------
# Loop fusion
#-------------------------------------------------------------------

# not optimized
function unfused(A,B,C)
    tmp = A .+ B
    tmp .+ C
end
@btime unfused(A,B,C) # 11.800 μs (4 allocations: 156.34 KiB)

# optimized
fused(A,B,C) = A .+ B .+ C
@btime fused(A,B,C) # 6.825 μs (2 allocations: 78.17 KiB)

# even more optimized
D = similar(A)
fused!(D,A,B,C) = (D .= A .+ B .+ C)
@btime fused!(D,A,B,C) # 3.375 μs (0 allocations: 0 bytes)

#! Note that while looping is slow in python, it isn't slow on Julia anyways, so do as you will...
#! also remember that bounds checking occur in loops, when indexing arrays

#-------------------------------------------------------------------
# Heap allocation from slicing
#-------------------------------------------------------------------

function ffa(B)
    B[1:5,1:5] # creates a new array
end

function ffas(B)
    @view B[1:5,1:5] # simply allocates a pointer to existing portion of an array
end

@btime ffa(A) # 65.275 ns (1 allocation: 256 bytes)
@btime ffas(A) # 22.289 ns (1 allocation: 64 bytes) ...note the smaller size as well..so this helps if you have small caches