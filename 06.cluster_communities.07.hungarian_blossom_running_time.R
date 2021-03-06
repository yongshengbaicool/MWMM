rm(list=ls())
ptm <- proc.time()
options(stringsAsFactors = F)
library("magrittr")

#------------------source functions below---------------------------------------

source(file.path(getwd(), "function_scripts_directory", "Hungarian_algorithm_function.R"))
source(file.path(getwd(), "function_scripts_directory", "cross_weight_functions.R"))
source(file.path(getwd(), "function_scripts_directory", "merge_blossom_matched_clusters.R"))

#------------------source functions above---------------------------------------



# -----------------input file setup.----------------------------------------------

# look up the input directory to get the cancer types.
TCGA_correlation_coefficient_tables_path <- file.path(getwd(), "input_data_directory", "TCGA_correlation_coefficient_tables")

cancer_types <- dir(TCGA_correlation_coefficient_tables_path) %>%
    strsplit(., "\\.") %>%
    sapply(., function(x) x[1][[1]])

# cancer_types <- rev(cancer_types)

for (cancer_type in cancer_types) {
    cancer_type <- "BRCA"
    raw_input_file_path <- file.path(getwd(),
                                     "output_data_directory",
                                     "plain_text_files",
                                     paste("six_kinds_of_weights_files", cancer_type, sep = "."),
                                     "integrated_mean_value_weight.csv")
    
    raw_edge_list_df <- read.csv(raw_input_file_path, check.names = F)[, 1:3]
    # "SLC35E2" is a duplicated gene. So it is removed.
    raw_edge_list_df <- raw_edge_list_df[raw_edge_list_df$mRNA != "SLC35E2", ]
    
    # make the raw graph and corresponding adjacency matrix from the input edge list.
    raw_graph <- graph.data.frame(raw_edge_list_df, directed = F)
    raw_adjacency_matrix <- as_adjacency_matrix(raw_graph, type="both", names=TRUE, sparse=FALSE, attr="weight")
    
    # create output directories
    dir.create(file.path(getwd(),
                         "output_data_directory",
                         "binary_object_files",
                         paste("communities_files", cancer_type, sep = ".")),
               showWarnings = F, recursive = T)
    dir.create(file.path(getwd(),
                         "output_data_directory",
                         "plain_text_files",
                         paste("cross_weight_and_blossom_matching", cancer_type, sep = ".")),
               showWarnings = F, recursive = T)
    
    ptm <- proc.time()
    # Run the Hungarian algorithm and get data analyzed.
    the_communities.hungarian_algorithm <- calculate_hungarian_algorithm(raw_input_file_path)
    path_to_output_file <- file.path(getwd(),
                                     "output_data_directory",
                                     "binary_object_files",
                                     paste("communities_files", cancer_type, sep = "."), 
                                     "the_communities.hungarian_algorithm.rds")
    saveRDS(the_communities.hungarian_algorithm, file = path_to_output_file)
    
    print("=======================================")
    cat("hungarian_algorithm", "has", length(communities(the_communities.hungarian_algorithm)), "clusters", sep = " ", "\n")
    print("=======================================")
    
    # calculate cross weight of the Hungarian results.
    the_communities.hungarian_algorithm <- readRDS(file.path(getwd(),
                                                             "output_data_directory",
                                                             "binary_object_files",
                                                             paste("communities_files", cancer_type, sep = "."),
                                                             "the_communities.hungarian_algorithm.rds"))

    cross_weight_df <- calculate_cross_weight_from_a_communities(the_communities.hungarian_algorithm, raw_edge_list_df)
    path_to_output_file <- file.path(getwd(),
                                     "output_data_directory",
                                     "plain_text_files",
                                     paste("cross_weight_and_blossom_matching", cancer_type, sep = "."),
                                     "cross_weight.hungarian_algorithm.csv")
    write.csv(cross_weight_df, file = path_to_output_file, quote = F, row.names = F)
    
    
    # run many rounds of blossom algorithms.
    counter <- 1
    previous_round <- "hungarian_algorithm"
    resultant_round <- "blossom_01"
    
    while (TRUE) {
        
        # blossom matching using python.
        path_to_python_script <- file.path(getwd(), "function_scripts_directory", "python_blossom_clustering.py")
        
        path_to_input_cross_weight_file <- file.path(getwd(),
                                                     "output_data_directory",
                                                     "plain_text_files",
                                                     paste("cross_weight_and_blossom_matching", cancer_type, sep = "."),
                                                     paste("cross_weight", previous_round,  "csv", sep = "."))
        
        path_to_output_blossom_matching_file <- file.path(getwd(),
                                                          "output_data_directory",
                                                          "plain_text_files",
                                                          paste("cross_weight_and_blossom_matching", cancer_type, sep = "."),
                                                          paste("maximum_matching", resultant_round, "csv", sep = "."))
        
        system2("python3", args = c(path_to_python_script,
                                   path_to_input_cross_weight_file,
                                   path_to_output_blossom_matching_file))
        
        # -----------------------------------------------------------------
        # merge blossom matched clusters.
        
        path_to_input_blossom_matching_file <- path_to_output_blossom_matching_file
        
        blossom_matching_df <- read.csv(path_to_input_blossom_matching_file, check.names = F)
        if(nrow(blossom_matching_df) == 0) {
            cat("Sorry,", resultant_round, "has no blossom matching result.", sep = " ", "\n")
            break
        }
        
        path_to_input_communities <- file.path(getwd(),
                                               "output_data_directory",
                                               "binary_object_files",
                                               paste("communities_files", cancer_type, sep = "."),
                                               paste("the_communities", previous_round, "rds", sep = "."))
        
        previous_communities <- readRDS(path_to_input_communities)
        
        resultant_communities <- merge_blossom_matching_clusters(previous_communities,
                                                                 path_to_input_blossom_matching_file,
                                                                 raw_edge_list_df)

        
        path_to_output_communities <- file.path(getwd(),
                                                "output_data_directory",
                                                "binary_object_files",
                                                paste("communities_files", cancer_type, sep = "."),
                                                paste("the_communities", resultant_round, "rds", sep = "."))
        saveRDS(resultant_communities, file = path_to_output_communities)
        
        
        # ---------------------------------------------------------------
        # cross-weight-blossom-result
        
        path_to_input_communities <- path_to_output_communities
        
        resultant_communities <- readRDS(path_to_input_communities)
        
        resultant_cross_weight_df <- calculate_cross_weight_from_a_communities(resultant_communities, raw_edge_list_df)
        
        path_to_output_cross_weight_file <- file.path(getwd(),
                                                      "output_data_directory",
                                                      "plain_text_files",
                                                      paste("cross_weight_and_blossom_matching", cancer_type, sep = "."),
                                                      paste("cross_weight", resultant_round, "csv", sep = "."))
        write.csv(resultant_cross_weight_df, file = path_to_output_cross_weight_file, quote = F, row.names = F)
        
        cat("Successful!", resultant_round, "has", length(communities(resultant_communities)), "clusters", sep = " ", "\n")
        print("=======================================")

        if (length(communities(resultant_communities)) < 2) {
            cat("Sorry,", resultant_round, "has only", length(communities(resultant_communities)), "cluster(s).", "Merging stops here.", sep = " ", "\n")
            break
        } else {
        # prepare for the next round of blossom.
            previous_round <- resultant_round
            counter <- counter + 1
            round_ordinal <- formatC(counter, digits = 1, flag = "0")
            resultant_round <- paste("blossom", round_ordinal, sep = "_")
            cat(resultant_round, "is coming", sep = " ", "\n")
        }
    }
    cat(cancer_type, "has done!", sep = " ", "\n")
    print("*****************************************************************")
    break
}



# ptm <- proc.time()
result_time <- proc.time() - ptm

output_dir <- file.path(getwd(), "output_data_directory", "plain_text_files")
output_file <- "hungarian_blossom_running_time.txt"
output_path <- file.path(output_dir, output_file)
cat("hungagrian_blossom", result_time["elapsed"], file = output_path, sep = ",", "\n")

proc.time() - ptm


