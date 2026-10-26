% Mistras AE MATLAB Library
% Version 26.10.26 (R2016b or later, no toolboxes required)
%
% Read, decode and analyse Acoustic Emission files from Mistras / Physical
% Acoustics AEwin software (.DTA hit and waveform files, .WFS streaming files).
%
% DTA files
%   AE_readDTA              - Parse a .DTA file once: setup, hits, waveforms.
%   AE_readHits_noPara      - Hit records as a struct array.
%   AE_listWaveforms        - Catalog table of all waveforms, paired to hits.
%   AE_plotWaveformByIndex  - Decode and plot one waveform.
%   AE_exportAllWaveforms   - Export every waveform to a .mat file.
%   AE_plotHits             - Hit-feature table and summary plots.
%
% WFS files
%   openWFS                 - Read a .WFS waveform streaming file.
%   ReadWFSHeader           - Parse the .WFS header tables.
%   ReadWFSDataTrunk        - Decode the .WFS data trunk.
%
% Analysis
%   AE_waveformSpectrum     - Amplitude spectrum, optional filter and normalisation.
%   AE_waveformFeatures     - Time, frequency, envelope and Hjorth features.
%   AE_wfsFolderFeatures    - Features of every .wfs in a folder, as a table.
%   AE_plotFeatureTrends    - Plot features against time.
%
% Demos and tests
%   DTA_Viewer, DTAtoMAT_Converter, WFSRunner, TestAELibrary
%
% Cite: https://doi.org/10.5281/zenodo.23519131
