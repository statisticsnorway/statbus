import React from 'react'
import PropTypes from 'prop-types'
import Dropzone from 'react-dropzone'
import { Message, Icon } from 'semantic-ui-react'

import { parseCSV, parseXML } from 'helpers/parseDataSourceAttributes'
import styles from './styles.pcss'

const { func } = PropTypes

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
    const file = files[0]
    const reader = new FileReader()
    try {
      reader.onload = (e) => {
        this.revokeCurrentFileUrl()
        const variablesMapping = []
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
      reader.readAsText(file)
    } catch (error) {
      this.setState({ fileError: localize('ParseFileError') })
    }
  }

  render() {
    const { localize } = this.props
    const { file, fileError } = this.state
    const [hasFile, hasError] = [file !== undefined, fileError !== undefined]
    return (
      <Dropzone
        ref={this.handleRef}
        onDrop={this.handleDropFile}
        multiple={false}
        className={styles['dz-container']}
      >
        <Message
          error={hasError}
          success={hasFile && !hasError}
        >
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
