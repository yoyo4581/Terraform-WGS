#rule to get basic alignment statistics, such as total reads, mapped reads, and duplicates.
rule flagstat:
    input:
        bam="mapped_reads/{cell_line}/sorted_{SRA}.bam"
    output:
        "results/{cell_line}/{SRA}/alignmentQC/flagstat_output.txt"
    shell:
        "samtools flagstat {input.bam} > {output}"

#more detailed, read length distribution, insert sizes, and mapping quality scores.
rule stats:
    input:
        bam = "mapped_reads/{cell_line}/sorted_{SRA}.bam"
    output:
        "results/{cell_line}/{SRA}/alignmentQC/alignment_stats.txt"
    threads: 4
    shell:
        "samtools stats {input.bam} > {output}"

#assess coverage across the genome, especially important in resequencing or variant calling.
rule bedCoverage:
    input:
        bam="mapped_reads/{cell_line}/{cell_line}_merged.bam",
    output:
        "results/{cell_line}/{cell_line}_coverage.bedgraph"
    threads: 4
    log:
        "logs/{cell_line}/{cell_line}_bedCoverage.log"
    shell:
        """
        bedtools genomecov -ibam {input.bam} -bga > {output}
        """

#comprehensive report including GC distribution, coverage uniformity, insert size distribution
rule qualimap:
    input:
        bam="mapped_reads/{cell_line}/sorted_{SRA}.bam"
    output:
        directory("results/{cell_line}/{SRA}/alignmentQC/qualimap_report/")
    threads: 4
    shell:
        "qualimap bamqc -bam {input.bam} -outdir {output} -c --java-mem-size=24G"

# alignment metrics including mismatch and error rates
rule qualiAlign:
    input:
        fa="data/GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa",
        bam="mapped_reads/{cell_line}/sorted_{SRA}.bam",
    output:
        "results/{cell_line}/{SRA}/alignmentQC/alignment_summary.txt"
    log:
        "logs/qualiAlign/{cell_line}/{SRA}.log"
    threads: 4
    shell:
        "java -Xmx24g -jar picard.jar CollectAlignmentSummaryMetrics R={input.fa} I={input.bam} O={output} > {log}"

# insert size metrics
rule insertMetrics:
    input:
        "mapped_reads/{cell_line}/sorted_{SRA}.bam"
    output:
        metrics="results/{cell_line}/{SRA}/alignmentQC/insert_size_metrics.txt",
        histogram="results/{cell_line}/{SRA}/alignmentQC/insert_size_histogram.pdf"
    log:
        "logs/insertMetrics/{cell_line}/{SRA}.log"
    shell:
        "java -Xmx24g -jar picard.jar CollectInsertSizeMetrics I={input} O={output.metrics} H={output.histogram} > {log}"

rule aggregateQC:
    input:
        [
            "results/{cell_line}/{SRA}/alignmentQC/flagstat_output.txt",
            "results/{cell_line}/{SRA}/alignmentQC/alignment_stats.txt",
            "results/{cell_line}/tumor_coverage.bedgraph",
            "results/{cell_line}/{SRA}/alignmentQC/qualimap_report/",
            "results/{cell_line}/{SRA}/alignmentQC/alignment_summary.txt",
            "results/{cell_line}/{SRA}/alignmentQC/insert_size_metrics.txt",
            "results/{cell_line}/{SRA}/alignmentQC/insert_size_histogram.pdf",
        ]
    output:
        "results/{cell_line}/{SRA}/alignmentMultiqc_report.html"
    threads: 4
    shell:
        """
        multiqc {input} -o results/{wildcards.cell_line}/{wildcards.SRA}/ --filename alignmentMultiqc_report.html
        """

