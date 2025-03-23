# Rule to generate FastQC reports on each forward/rev of each run
rule preQC_report:
    input:
        forw="data/samples/{SRA}/{SRA}_1.fastq.gz",
        reve="data/samples/{SRA}/{SRA}_2.fastq.gz"
    output:
        directory("results/{cell_line}/{SRA}/prefastQC")
    shell:
        """
        mkdir -p results/{wildcards.cell_line}/{wildcards.SRA}/prefastQC && \
        fastqc {input.forw} {input.reve} -o results/{wildcards.cell_line}/{wildcards.SRA}/prefastQC
        """

# Rule to generate MultiQC report in a results directory organized by cell line
rule preMultiQC:
    input:
        "results/{cell_line}/{SRA}/prefastQC/",
    output:
        "results/{cell_line}/preMultiqc_report.html"
    shell:
        """
        multiqc {input} -o results/{wildcards.cell_line}/ --filename preMultiqc_report.html
        """

rule trim:
    input:
        reads=["data/samples/{wildcards.SRA}/{wildcards.SRA}_1.fastq.gz", "data/samples/{SRA}/{SRA}_2.fastq.gz"]
    output:
        protected("trimmed_reads/{wildcards.cell_line}/{wildcards.SRA}/{wildcards.SRA}_1_trimmed_paired.fastq.gz"),
        protected("trimmed_reads/{wildcards.cell_line}/{wildcards.SRA}/{wildcards.SRA}_2_trimmed_paired.fastq.gz"),
        protected("trimmed_reads/{wildcards.cell_line}/{wildcards.SRA}/{wildcards.SRA}_1_trimmed_unpaired.fastq.gz"),
        protected("trimmed_reads/{wildcards.cell_line}/{wildcards.SRA}/{wildcards.SRA}_2_trimmed_unpaired.fastq.gz")
    params:
        adapter_file="adapters/TruSeq3-PE.fa"
    shell:
        """
        trimmomatic PE -phred33 \
        {input.reads[0]} {input.reads[1]} \
        {output[0]} {output[2]} \
        {output[1]} {output[3]} \
        ILLUMINACLIP:{params.adapter_file}:2:30:10 \
        SLIDINGWINDOW:4:30 \
        MINLEN:75
        """


# Rule to generate FastQC reports on each forward/rev of each run
rule postQC_report:
    input:
        forw="trimmed_reads/{cell_line}/{SRA}/{SRA}_1_trimmed_paired.fastq.gz",
        reve="trimmed_reads/{cell_line}/{SRA}/{SRA}_2_trimmed_paired.fastq.gz"
    output:
        directory("results/{cell_line}/{SRA}/postfastQC")
    shell:
        """
        mkdir -p results/{wildcards.cell_line}/{wildcards.SRA}/postfastQC && \
        fastqc {input.forw} {input.reve} -o results/{wildcards.cell_line}/{wildcards.SRA}/postfastQC
        """


# Rule to generate MultiQC report in a results directory organized by cell line
rule postMultiQC:
    input:
        lambda wildcards: expand(
            "results/{cell_line}/{SRA}/postfastQC/",
            cell_line=wildcards.cell_line,
            SRA=config["metadata"][wildcards.cell_line]
        )
    output:
        html="results/{cell_line}/postMultiqc_report.html"
    shell:
        """
        multiqc {input} -o results/{wildcards.cell_line}/ --filename postMultiqc_report.html
        """


rule bwa_mem:
    input:
        reads=["trimmed_reads/{cell_line}/{SRA}/{SRA}_1_trimmed_paired.fastq.gz", 
        "trimmed_reads/{cell_line}/{SRA}/{SRA}_2_trimmed_paired.fastq.gz"],
        idx="data/GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa.ann",
    output:
        protected("mapped_reads/{cell_line}/sorted_{SRA}.bam")
    log:
        "logs/bwa_mem/{cell_line}/{SRA}.log",
    params:
        extra=lambda wildcards: f"-R '@RG\\tID:{wildcards.SRA}\\tPL:ILLUMINA\\tLB:{wildcards.cell_line}_lib1\\tSM:{wildcards.cell_line}\\tPI:300'",
        sorting="samtools",
        sort_order="coordinate",
        sort_extra="",
    threads: 8
    wrapper:
        "v5.0.0/bio/bwa/mem"


rule deleteSamples:
    input:
        lambda wildcards: expand(
            "mapped_reads/{cell_line}/sorted_{SRA}.bam",
            cell_line=wildcards.cell_line,
            SRA=config["metadata"][wildcards.cell_line]
        )
    output:
        "data/deletedSamples.txt"
    shell:
        """
        rm -r data/samples
        echo "Samples Deleted after processing" > {output}
        """


rule samtools_index:
    input:
        "mapped_reads/{cell_line}/sorted_{SRA}.bam"
    output:
        "mapped_reads/{cell_line}/sorted_{SRA}.bam.bai"
    shell:
        "samtools index {input}"