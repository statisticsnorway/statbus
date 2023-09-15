import React, { useState, useEffect } from 'react'
import { func, number, string, oneOfType } from 'prop-types'
import Dropzone from 'react-dropzone'
import { Message, Icon } from 'semantic-ui-react'

import { fromCsv, fromXml } from 'helpers/parseDataSourceAttributes'
import styles from './styles.pcss'

function TemplateFileAttributesParser({ csvDelimiter, csvSkipCount, onChange, localize }) {
  const [file, setFile] = useState(undefined)
  const [fileError, setFileError] = useState(undefined)

  useEffect(() => () => {
    revokeCurrentFileUrl()
  }, [])

  const revokeCurrentFileUrl = () => {
    if (file) URL.revokeObjectURL(file.preview)
  }

  const parseFile = () => {
    const reader = new FileReader()
    reader.onload = (e) => {
      const raw = e.target.result
      revokeCurrentFileUrl()
      const nextValues = { variablesMapping: [], csvDelimiter, csvSkipCount }
      if (file.name.endsWith('.csv')) {
        const parsed = fromCsv(raw)
        nextValues.attributesToCheck = parsed.attributes
        nextValues.csvSkipCount = parsed.startFrom
        nextValues.csvDelimiter = parsed.delimiter
      } else if (file.name.endsWith('.xml')) {
        nextValues.attributesToCheck = fromXml(raw)
      } else {
        nextValues.attributesToCheck = []
      }
      setFileError(nextValues.attributesToCheck.length === 0 ? localize('ParseAttributesNotFound') : undefined)
      onChange(nextValues)
    }
    try {
      reader.readAsText(file)
    } catch (error) {
      setFileError(localize('ParseFileError'))
    }
  }

  const handleRef = (dz) => {
    this.dropzone = dz
  }

  const handleDropFile = (files) => {
    setFile(files[0])
    parseFile()
  }

  const hasFile = file !== undefined
  const hasError = fileError !== undefined
  const color = hasError ? 'red' : hasFile ? 'olive' : undefined

  return (
    <Dropzone
      ref={handleRef}
      accept=".csv, .xml"
      onDrop={handleDropFile}
      multiple={false}
      className={styles['dz-container']}
    >
      <Message
        header={localize('DropXmlOrCsvFileAmigo')}
        content={
          hasFile && (
            <div>
              <p>
                <Icon name={hasError ? 'close' : 'check'} /> {file.name}
              </p>
              <p>{fileError}</p>
            </div>
          )
        }
        icon="upload"
        color={color}
      />
    </Dropzone>
  )
}

TemplateFileAttributesParser.propTypes = {
  csvDelimiter: string.isRequired,
  csvSkipCount: oneOfType([string, number]).isRequired,
  onChange: func.isRequired,
  localize: func.isRequired,
}

export default TemplateFileAttributesParser
