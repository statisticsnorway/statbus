import React from 'react'
import { func, number, string, oneOfType } from 'prop-types'
import Dropzone from 'react-dropzone'
import { Message, Icon } from 'semantic-ui-react'

import { fromCsv, fromXml } from 'helpers/parseDataSourceAttributes'
import styles from './styles.pcss'

class TemplateFileAttributesParser extends React.Component {
  static propTypes = {
    csvDelimiter: string.isRequired,
    csvSkipCount: oneOfType([string, number]).isRequired,
    onChange: func.isRequired,
    localize: func.isRequired,
  }

  state = {
    file: undefined,
    fileError: undefined,
  }

  componentWillUnmount() {
    this.revokeCurrentFileUrl()
  }

  revokeCurrentFileUrl() {
    const { file } = this.state
    if (file) URL.revokeObjectURL(file.preview)
  }

  parseFile = () => {
    const { csvDelimiter, csvSkipCount, localize, onChange } = this.props
    const { file } = this.state
    const reader = new FileReader()
    reader.onload = (e) => {
      const raw = e.target.result
      this.revokeCurrentFileUrl()
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
      this.setState(
        {
          fileError:
            nextValues.attributesToCheck.length === 0
              ? localize('ParseAttributesNotFound')
              : undefined,
        },
        () => onChange(nextValues),
      )
    }
    try {
      reader.readAsText(file)
    } catch (error) {
      this.setState({ fileError: localize('ParseFileError') })
    }
  }

  handleRef = (dz) => {
    this.dropzone = dz
  }

  handleDropFile = (files) => {
    this.setState({ file: files[0] }, this.parseFile)
  }

  render() {
    const { localize } = this.props
    const { file, fileError } = this.state
    const [hasFile, hasError] = [file !== undefined, fileError !== undefined]
    const color = hasError ? 'red' : hasFile ? 'olive' : undefined
    return (
      <Dropzone
        ref={this.handleRef}
        onDrop={this.handleDropFile}
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
}

export default TemplateFileAttributesParser
