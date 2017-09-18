import React from 'react'
import { func } from 'prop-types'
import Dropzone from 'react-dropzone'
import { Message, Icon } from 'semantic-ui-react'

import { parseCSV, parseXML } from 'helpers/parseDataSourceAttributes'
import styles from './styles.pcss'

class TemplateFileAttributesParser extends React.Component {

  static propTypes = {
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

  handleRef = (dz) => { this.dropzone = dz }

  handleDropFile = (files) => {
    const { localize, onChange } = this.props
    const [file, reader, variablesMapping] = [files[0], new FileReader(), []]

    reader.onload = (e) => {
      this.revokeCurrentFileUrl()
      const attributesToCheck = file.name.endsWith('.xml')
        ? parseXML(e.target.result)
        : file.name.endsWith('.csv')
          ? parseCSV(e.target.result)
          : []
      const [nextState, nextValues] = attributesToCheck.length === 0
        ? [{ fileError: localize('ParseAttributesNotFound') }, { variablesMapping }]
        : [{ file, fileError: undefined }, { attributesToCheck, variablesMapping }]
      this.setState(nextState, () => { onChange(nextValues) })
    }

    try {
      reader.readAsText(file)
    } catch (error) {
      this.setState({ fileError: localize('ParseFileError') })
    }
  }

  render() {
    const [{ localize }, { file, fileError }] = [this.props, this.state]
    const [hasFile, hasError] = [file !== undefined, fileError !== undefined]
    const color = hasError ? 'red' : hasFile ? 'green' : undefined
    return (
      <Dropzone
        ref={this.handleRef}
        onDrop={this.handleDropFile}
        multiple={false}
        className={styles['dz-container']}
      >
        <Message color={color}>
          <Icon name="upload" size="huge" />
          <Message.Content>
            <Message.Header content={localize('DropXmlOrCsvFileAmigo')} />
            {!hasError && hasFile &&
              <p><Icon name="check" />{file.name}</p>}
            {hasError &&
              <p><Icon name="close" />{fileError}</p>}
          </Message.Content>
        </Message>
      </Dropzone>
    )
  }
}

export default TemplateFileAttributesParser
