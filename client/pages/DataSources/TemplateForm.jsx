import React from 'react'
import { Icon, Message } from 'semantic-ui-react'
import Dropzone from 'react-dropzone'

import { parseCSV, parseXML } from 'helpers/parseDataSourceAttributes'
import styles from './styles.pcss'

class TemplateForm extends React.Component {

  state = {
    formData: this.props.formData || schema.default(),
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

  handleDropFile = (files) => {
    const file = files[0]
    const reader = new FileReader()
    try {
      reader.onload = (e) => {
        this.revokeCurrentFileUrl()
        const attribs = file.name.endsWith('.xml')
          ? parseXML(e.target.result)
          : file.name.endsWith('.csv')
            ? parseCSV(e.target.result)
            : []
        if (attribs.length === 0) {
          this.setState(prev => ({
            fileError: this.props.localize('ParseAttributesNotFound'),
            formData: { ...prev.formData, variablesMapping: [] },
          }))
        } else {
          this.setState(prev => ({
            file,
            fileError: undefined,
            formData: {
              ...prev.formData,
              variablesMapping: [],
              attributesToCheck: attribs,
            },
          }))
        }
      }
      reader.readAsText(file)
    } catch (error) {
      this.setState({ fileError: this.props.localize('ParseFileError') })
    }
  }

  handleSubmit = () => {
    const { formData } = this.state
    const variablesMapping = formData.variablesMapping
      .map(pair => `${pair[0]}-${pair[1]}`)
      .join(',')
    this.props.submitData({
      ...formData,
      variablesMapping,
    })
  }

  renderDropzone() {
    const { localize } = this.props
    const { file, fileError } = this.state
    return (
      <Dropzone
        ref={(dz) => { this.dropzone = dz }}
        onDrop={this.handleDropFile}
        multiple={false}
        className={styles['dz-container']}
      >
        <Message
          error={fileError !== undefined}
          success={fileError === undefined && file !== undefined}
        >
          <Icon name="upload" size="huge" />
          <Message.Content>
            <Message.Header content={localize('DropXmlOrCsvFileAmigo')} />
            {!fileError && file && <p><Icon name="check" />{file.name}</p>}
            {fileError && <p><Icon name="close" />{fileError}</p>}
          </Message.Content>
        </Message>
      </Dropzone>
    )
  }
}
